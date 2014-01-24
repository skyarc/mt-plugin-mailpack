package MTCMS::Image::GD;

use strict;
use warnings;
use MT::Image::GD;
use MTCMS::Image;
use base qw(MTCMS::Image MT::Image::GD);

# return rotated image.
sub rotate {
        my ($image, $degree) = @_;

    my $src = $image->{gd};
    my $gd;

        if($degree == 0) {
                $gd = $src;
        } elsif($degree == 90) {
                $gd = $src->copyRotate90;
        } elsif ($degree == 180) {
                $gd = $src->copyRotate180;
        } elsif ($degree == 270) {
                $gd = $src->copyRotate270;
        } else {
                return $image->error(MT->translate("Rotationg [_1] degree is currently not supported in GD.", $degree));
        }

        my ($w, $h) = $image->{gd}->getBounds();
    ($image->{gd}, $image->{width}, $image->{height}) = ($gd, $w, $h);
    wantarray ? ($image->blob, $w, $h) : $image->blob;
}

# flip
sub flip_horizontal {
        my ($image) = @_;

    my $src = $image->{gd};
        $src->flipHorizontal;

    wantarray ? ($image->blob, $image->{width}, $image->{height}) : $image->blob;
}

1;
