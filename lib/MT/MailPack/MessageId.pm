package MT::MailPack::MessageId;
use strict;
use warnings;

use MT::Object;
@MT::MailPack::MessageId::ISA = qw(MT::Object);

__PACKAGE__->install_properties ({
    column_defs => {
        'id' => 'integer not null auto_increment',
        'obj_id' => 'integer not null',
        'obj_type' => 'integer not null',
        'hash' => 'string(32) not null',
    },
    indexes => {
        hash => 1,
    },
    primary_key => 'id',
    datasource => 'mp_messageid',
});

sub ENTRY ()    { 1 }
sub COMMENT ()  { 2 }

sub class_label {
    'Mailpack Message Thereading';
}

1;
__END__
