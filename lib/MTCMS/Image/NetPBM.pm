package MTCMS::Image::NetPBM;

use strict;
use warnings;

use MT::Image::NetPBM;
use MTCMS::Image;
use base qw(MTCMS::Image MT::Image::NetPBM);

sub rotate {
    my ($image, $degree) = @_;
    return $image->error(MT->translate("Image rotation with NetPBM is currently not supported."));
}

1;
