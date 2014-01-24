package cleanup;

use strict;
use warnings;
use Exporter;
@cleanup::ISA = qw(Exporter);
use vars qw(@EXPORT_OK);
@EXPORT_OK = qw(analisismail);
use logmgr;
use logmgr qw(add_logque);


# SubRoutine======================================
sub analisismail {
    my ($plugin, $maildrop_ref,$logque_ref) = @_;
    my @maildrop = @$maildrop_ref;
    my @logque = @$logque_ref;
    my @inbound;
    my $del_count = 0;
    eval {
        while (@maildrop) {
            my $entity = shift(@maildrop);
            my $head = $entity->head;
#            $head->decode;
            my $type = $head->get('Content-Type');

            if ($entity->is_multipart){
                if ($type =~ m!(multipart/mixed)!i) {
                    push(@inbound,$entity);
                } elsif ($type =~ m!(multipart/alternative)!i) {
                    push(@inbound,$entity);
                } elsif ($type =~ m!(multipart/parallel)!i) {
                    $del_count++;
                } elsif ($type =~ m!(multipart/digest)!i) {
                    $del_count++;
                } else{
                    $del_count++;
                }
            }else{

                unless( $type )
                {
                    $del_count++;
                    next;
                }

                if ($type =~ m!(text/plain)!i) {
                    push(@inbound,$entity);
                } elsif ($type =~ m!(image/.)!i) {
                    push(@inbound,$entity);
                } elsif ($type =~ m!(audio/.)!i) {
                    push(@inbound,$entity);
                } elsif ($type =~ m!(video/.)!i) {
                    push(@inbound,$entity);
                } elsif ($type =~ m!(application/.)!i) {
                    if ($type =~ m!(application/ms-tnef)!i) {
                        # 未対応
                        $del_count++;
                    } elsif ($type =~ m!(application/pgp-.*)!i) {
                        # 未対応
                        $del_count++;
                    } else {
                        push(@inbound,$entity);
                    }
                } else {
                    # 未対応
                    $del_count++;
                }
            }
        }
        if ($del_count > 0){
            push(@logque, add_logque(MT::Log->INFO, 0, $plugin->translate('MailPack: The mail not accepted was deleted ([_1] mails).', $del_count)));
        }
    };
    if ($@) {
        push(@logque, add_logque(MT::Log->ERROR, 0, '[MailPack] cleanup.pm ' . $@));
    }
    return (\@inbound,\@logque);
}
#=================================================



1;
__END__
