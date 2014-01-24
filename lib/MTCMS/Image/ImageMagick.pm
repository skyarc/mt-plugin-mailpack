package MTCMS::Image::ImageMagick;

use strict;
use warnings;

use MT::Image::ImageMagick;
use MTCMS::Image;
use base qw(MTCMS::Image MT::Image::ImageMagick);

# orverride
sub rotate_by_orientation {
    my ($image, $orientation) = @_;

    my $degree = MTCMS::Image::_rotation_by_orientation($orientation);
    return $image->rotate($degree); 

}

# return rotated image.
sub rotate {
    my ($image, $degree) = @_;

    my $magick = $image->{magick};
    if ( $magick->can('Profile') ) {
         $magick->Profile('profile' => '');
    }
    my $err = $magick->Rotate($degree);
    return $image->error(MT->translate(
        "Rotating to [_1] failed: [_2]", $degree, $err)) if $err;

        my ($w, $h) = $magick->Get(qw(width height));
    ($image->{width}, $image->{height}) = ($w, $h);
    wantarray ? ($magick->ImageToBlob, $w, $h) : $magick->ImageToBlob;
}

1;

__END__
