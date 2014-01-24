package logmgr;

use strict;
use warnings;
use Exporter;
@logmgr::ISA = qw(Exporter);
use vars qw(@EXPORT_OK);
@EXPORT_OK = qw(logmgr add_logque get_plugin_data);



# SubRoutine======================================
sub logmgr {
    my ($plugin, $logque_ref) = @_;
    my @logque = @$logque_ref;
    eval {
        require MT::Log;
        require MT::Author;
        require MT::Blog;
        require MT::Mail;

        foreach my $mp_log (@logque) {
            if ($mp_log){
                my $log = MT::Log->new();
                $log->level($mp_log->{log_level});
                $log->message($mp_log->{log_msg});
                $log->blog_id($mp_log->{log_blog_id});
                $log->author_id($mp_log->{log_author_id});
                if ($mp_log->{log_time}){
                    my @ts = gmtime($mp_log->{log_time});
                    my $ts = sprintf '%04d%02d%02d%02d%02d%02d', $ts[5]+1900, $ts[4]+1, @ts[3,2,1,0];
                    $log->modified_on($ts);
                    $log->created_on($ts);
                }
                $log->save;
            }
        }

        foreach my $log_rec (@logque) {
            if ($log_rec){
                if (($log_rec->{log_level} > 1) && ($log_rec->{log_author_id}) && ($log_rec->{log_blog_id}) && ($log_rec->{log_send_email} ne '')){
                    my $blog   = MT::Blog->load($log_rec->{log_blog_id});
                    my $author = MT::Author->load($log_rec->{log_author_id});

                    my $subject = $plugin->translate('MailPack: Blog:[_1] mail entry error', $blog->name);
                    $subject =~ s/&amp;/&/g;
                    $subject =~ s/&lt;/</g;
                    $subject =~ s/&gt;/>/g;

                    my $to      = $author->email;
                    my $from    = $log_rec->{log_send_email};
                    my $body    = $log_rec->{log_msg};
                    if ($body){
                        $body =~ s/<br/\n<br/ig;
                        $body =~ s/<\/p/\n\n<\/p/ig;
                        $body =~ s/<.*?>//g;
                        $body =~ s!&nbsp;! !g;
                    }
                    $body .= "\n\n" . 'URL: ' . $blog->site_url . " \n";
                    $body = MT::Util::decode_html($body);
					MT->log($body);

                    my %head = ( From => $from, To => $to, Subject => $subject);
                    MT::Mail->send(\%head, $body);
                }
            }
        }

    };
    if ($@) {
        my $log = MT::Log->new;
        $log->message( 'MailPack: ' . $@);
        $log->level( MT::Log->WARNING );
        MT->log( $log );
    }
}

# ログキュー登録(サブルーチン化して各モジュールにて使用)
sub add_logque{
    my ($log_level,$log_time,$log_msg,$log_blog_id,$log_author_id, $log_send_email) = @_;
    my $buf_log;
    my $blog_id = $log_blog_id || 0;
    my $author_id = $log_author_id || 0;
    my $send_email = $log_send_email || '';
    eval {
        if ($log_time == 0){
            $log_time = time();
        }
        $buf_log = {
            log_level => $log_level,
            log_time => $log_time,
            log_msg => $log_msg,
            log_blog_id => $blog_id,
            log_author_id => $author_id,
            log_send_email => $send_email,
        };
    };
    if ($@) {
    }
    return $buf_log;
}

#=================================================

sub get_plugin_data {
    my ($plugin, $blog_id, $fields) = @_;
    my %plugin_param;
    my $key;

    require MT::PluginData;
    my $data = MT::PluginData->load({ plugin => 'MailPack', key=> 'configuration:blog:' . $blog_id});

    if ($data){
        $plugin->load_config(\%plugin_param, 'blog:'.$blog_id);
        $key = $plugin_param{$fields};
    }else{
        $plugin->load_config(\%plugin_param, 'system');
        $key = $plugin_param{$fields};
    }
    return $key;
}


1;
__END__
