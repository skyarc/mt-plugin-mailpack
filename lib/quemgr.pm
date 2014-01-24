package quemgr;

use strict;
use warnings;
use Exporter;
@quemgr::ISA = qw( Exporter );
use vars qw( @EXPORT_OK );
@EXPORT_OK = qw( quemgr );
use listner qw( getmail );
use cleanup qw( analisismail );
use create qw( createblogque );
use post_entry qw( post_entry );
use notification qw( notification_mail );
use logmgr qw( logmgr add_logque );
use File::Spec;
use File::Basename;

my $debug = 0;
## 受信したメールの一時的な保存先ディレクトリの指定
sub default_tmpdir {
    return File::Spec->catdir( File::Basename::dirname( __FILE__ ) , 'tmp' );
}
sub mailpack_tmpdir {

    my $plugin = MT->component('mailpack');
    my $tmpdir = '';
    if ( defined $plugin && $plugin ) 
    {
        $tmpdir = $plugin->tmpdir;
    }
    $tmpdir = default_tmpdir() unless $tmpdir;
    return $tmpdir;

}

sub quemgr {
    my $plugin = shift;
    my (@maildrop, @inbound, @outbound, @logque);
    my ($maildrop_ref, $inbound_ref, $outbound_ref, $logque_ref, $entry_ref);
    eval {

        # 作業ディレクトリの準備
        my $tmpdir = mailpack_tmpdir();
        if ( MT->config->DebugMode && $debug ) {
           MT->log( "MailPack Temporary Directory ($tmpdir)" );
        }
        die $plugin->translate("Temporary path is invalid.") unless defined $tmpdir && $tmpdir;
        mkdir $tmpdir , 0777 unless -d $tmpdir;
        die $plugin->translate("Can not write to temporary. Please check the permissions. ( [_1] )" , $tmpdir) unless -w $tmpdir;

        ($maildrop_ref, $logque_ref) = getmail ($plugin , $tmpdir);
        ($inbound_ref, $logque_ref) = analisismail ($plugin, $maildrop_ref, $logque_ref);
        ($outbound_ref, $logque_ref) = createblogque ($plugin, $inbound_ref, $logque_ref);
        ($entry_ref, $logque_ref) = post_entry ($plugin, $outbound_ref, $logque_ref);
        $logque_ref = notification_mail ($plugin, $entry_ref, $logque_ref);
        logmgr ($plugin, $logque_ref);

        # 作業ディレクトリの削除
        require File::Path;
        File::Path::rmtree( $tmpdir )
            or die $plugin->translate( "Failed to delete directory ( [_1] )" , $tmpdir );

    };
    if ($@) {
        my $log = MT::Log->new;
        $log->message ('MailPack: ' . $@);
        $log->level (MT::Log->WARNING());
        MT->log ($log);
    }
}

1;
