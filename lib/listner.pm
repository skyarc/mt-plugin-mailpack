package listner;

use strict;
use warnings;
use Exporter;
@listner::ISA = qw(Exporter);
use vars qw(@EXPORT_OK);
@EXPORT_OK = qw(getmail);
use logmgr qw(add_logque);

sub getmail {
    my ($plugin , $tmpdir) = @_;
    my @maildrop = ();
    my @logque   = ();
    eval {
        my @mpa_list = MT::Mailpackaddress->load();
        my %tmp;
        my @ref_array = grep { !$tmp{$_->email}++ } @mpa_list;
        foreach (@ref_array) {
            my $hostname = $_->pop3;
            my $username = $_->user;
            my $password = $_->pass;
            my $blog_id  = $_->blog_id;
            my $cate_id  = $_->category_id;
            my $email    = $_->email;
            my $port     = $_->port;
            my $ssl_flg  = $_->ssl_flg;

            my ($maildrop, $logque);
            if ($ssl_flg == 1)
            {
                ($maildrop, $logque) = &get_ssl_mailbox (
                   $plugin,
                   \@maildrop,
                   \@logque,
                   $hostname,
                   $username,
                   $password,
                   $email,
                   $port,
                   $blog_id,
                   $tmpdir
                );
            }
            else
            {
                ($maildrop, $logque) = &get_mailbox (
                   $plugin,
                   \@maildrop,
                   \@logque,
                   $hostname,
                   $username,
                   $password,
                   $email,
                   $port,
                   $blog_id,
                   $tmpdir
                );
            }
            @maildrop = @$maildrop;
            @logque   = @$logque;
        }
    };
    if ($@) {
        push (@logque, add_logque (MT::Log->ERROR, 0, '[MailPack] listner.pm ' . $@));
    }
    return (\@maildrop, \@logque);
}



sub get_mailbox{
    my ($plugin, $maildrop, $logque,  $hostname, $username, $password, $email, $port, $blog_id, $tmpdir) = @_;
    my @maildrop = @$maildrop;
    my @logque   = @$logque;

    require Net::POP3;
    require MIME::KbParser;
    require MT::Blog;
    require MT::Entry;
    require MT::Author;
    require MT::Category;
    require MT::Log;

    my $pop = Net::POP3->new($hostname, Timeout=> 120);
    if (! $pop){
        push(@logque, add_logque(MT::Log->ERROR, 0, $plugin->translate('MailPack: POP server connect error: [_1]', $email), $blog_id));
        return(\@maildrop,\@logque);
    }
    my $checklogin = $pop->login($username, $password);
    if (! $checklogin){
        push(@logque, add_logque(MT::Log->ERROR, 0, $plugin->translate('MailPack: POP server attestation error: [_1]', $email), $blog_id));
        return(\@maildrop,\@logque);
    }

    my $maillist = $pop->list;
    my $count = 0;

    my $parser = MIME::KbParser->new;
    #添付ファイルがMIMEデータの場合でも、添付ファイルとして処理させる
    $parser->extract_nested_messages(0);

    ##作業ディレクトリ指定
    $parser->output_dir($tmpdir);

    foreach my $msg_id (sort keys %$maillist) {
      my $fh = $pop->getfh($msg_id);
      my $entity = $parser->parse($fh);
      $entity->{mail_box} = $email;

      push(@maildrop,$entity);
      # entity格納後、メールは削除する
      $pop->delete ($msg_id);#DEBUG
      $count++;
    }
    #メール処理件数が０件の場合は、ログを出力しない
    if ($count > 0){
      push(@logque, add_logque(MT::Log->INFO, 0, $plugin->translate('MailPack: [_1] mail reception and delete ([_2] mails).', $email, $count), $blog_id));
    }
    $pop->quit;

    return(\@maildrop,\@logque);
}

sub get_ssl_mailbox{
    my ($plugin, $maildrop, $logque,  $hostname, $username, $password, $email, $port, $blog_id, $tmpdir) = @_;
    my @maildrop = @$maildrop;
    my @logque   = @$logque;

    eval{require Mail::POP3Client;};
    if ($@){
        push(@logque, add_logque(MT::Log->ERROR, 0, $plugin->translate('MailPack: POP over SSL need Mail::POP3Client [_1]', $email), $blog_id));
        return(\@maildrop,\@logque);
    }
    eval{require IO::Socket::SSL;};
    if ($@){
        push(@logque, add_logque(MT::Log->ERROR, 0, $plugin->translate('MailPack: POP over SSL need IO::Socket::SSL [_1]', $email), $blog_id));
        return(\@maildrop,\@logque);
    }

    require MIME::KbParser;
    require MT::Blog;
    require MT::Entry;
    require MT::Author;
    require MT::Category;
    require MT::Log;

    my $pop = Mail::POP3Client->new(
        HOST     => $hostname,
        USER     => $username,
        PASSWORD => $password,
        USESSL   => 1,
        PORT     => $port,
        TIMEOUT  => 10,
#       AUTH => "PASS",
    );
    unless ($pop->Alive){
        push(@logque, add_logque(MT::Log->ERROR, 0, $plugin->translate('MailPack: POP server connect error: [_1]', $email), $blog_id));
        return(\@maildrop,\@logque);
    }
    my $mail_count = $pop->Count;
    my $count = 0;

    my $parser = new MIME::KbParser;
    #添付ファイルがMIMEデータの場合でも、添付ファイルとして処理させる
    $parser->extract_nested_messages(0);

    ## 作業ディレクトリ指定
    $parser->output_dir($tmpdir);

    for (my $i=0; $i<=$mail_count-1; ++$i) {
        my $entity = $parser->parse_data(join("\n", $pop->HeadAndBody($i+1)));
        $entity->{mail_box} = $email;
        push(@maildrop,$entity);
        # entity格納後、メールは削除する
        $pop->Delete($i+1);
        $count++;
    }
    #メール処理件数が０件の場合は、ログを出力しない
    if ($count > 0){
        push(@logque, add_logque(MT::Log->INFO, 0, $plugin->translate('MailPack: [_1] mail reception and delete ([_2] mails).', $email, $count), $blog_id));
    }
    $pop->Close;

    return(\@maildrop,\@logque);
}

1;
__END__
