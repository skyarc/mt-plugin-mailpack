package notification;

use strict;
use warnings;
use Exporter;
@notification::ISA = qw(Exporter);
use vars qw(@EXPORT_OK);
@EXPORT_OK = qw(notification_mail);
use logmgr;
use logmgr qw(add_logque);


# SubRoutine======================================
sub notification_mail {
    my ($plugin, $entry_ref,$logque_ref) = @_;
    my @entry_arrs = @$entry_ref;
    my @logque = @$logque_ref;
    eval {
        require MT::Blog;
        require MT::Entry;
        require MT::Mail;
        require MT::Permission;
        require MT::Author;

        foreach my $entry_rec (@entry_arrs) {
            my $entry = MT::Entry->load($entry_rec->{entry_id});
            if ($entry){
                my $notification_flg       = get_plugin_data($plugin, $entry->blog_id, 'notification_flg');
                my $notification_superuser = get_plugin_data($plugin, $entry->blog_id, 'notification_superuser');
                my $notification_subject   = get_plugin_data($plugin, $entry->blog_id, 'notification_subject');
                if ($notification_flg eq "0"){
                    next;
                }

                # entry_status check
                unless ($entry->status == 2){
                    next;
                }

                my $from  = $entry_rec->{send_email};

                my $subject = $notification_subject . $entry->title;
                my $title = $subject;
                $title =~ s/&amp;/&/g;
                $title =~ s/&lt;/</g;
                $title =~ s/&gt;/>/g;

                my $body = $entry->text;
                $body =~ s/<br/\n<br/ig;
                $body =~ s/<\/p/\n\n<\/p/ig;
                $body =~ s/<.*?>//g;
                $body =~ s!&nbsp;! !g;
                $body .= "\n" . 'URL: ' . $entry->permalink . " \n";
                $body = MT::Util::decode_html($body);

                my @send_list = ();
                #ブログに所属するユーザ
                my $iter = MT::Permission->load_iter({ blog_id => $entry->blog_id});
                while(my $perms = $iter->()) {
                    my $author = MT::Author->load({id => $perms->author_id});
                    if ($author){
                        unless ($author->status == 2){
                            if ($author->email){
                                push(@send_list, $author->email);
                            }
                        }
                    }
                }
                #システム管理者を対象に含める
                if ($notification_superuser eq "1"){
                    my $author_iter = MT::Author->load_iter({});
                    while (my $author_data = $author_iter->()) {
                        if ($author_data->is_superuser){
                            unless ($author_data->status == 2){
                                if ($author_data->email){
                                    push(@send_list, $author_data->email);
                                }
                            }
                        }
                    }
                }
                my %tmp = ();
                @send_list = grep(!$tmp{$_}++, @send_list );
                #メール送信処理
                my $send_count = 0;
                foreach my $email (@send_list) {
                    if ($email){
                        my %head = ( From => $from, To => $email, Subject => $title);
                        unless (MT::Mail->send(\%head, $body)){
                            push(@logque, add_logque(MT::Log->ERROR, 0, $plugin->translate('MailPack: Entry:[_1] send error notification mail. to:([_2])', $entry->title, $email), $entry->blog_id, $entry->author_id));
                        }else{
                            $send_count++;
                        }
                    }
                }
                if ($send_count > 0){
                    push(@logque, add_logque(MT::Log->INFO, 0, $plugin->translate('MailPack: Entry:[_1] send notification mail. count:([_2])', $entry->title, $send_count), $entry->blog_id, $entry->author_id));
                }
            }
        }
    };
    if ($@) {
        push(@logque, add_logque(MT::Log->ERROR, 0, '[MailPack] notification.pm ' . $@));
    }
    return \@logque;
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
