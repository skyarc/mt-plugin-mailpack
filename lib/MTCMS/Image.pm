use strict;
use MT;
use MT::Image;

use Exif::Simple;

use Data::Dumper;

package MTCMS::Image;

use base qw(MT::Image);

#sub new {
#	my $class = shift;
#	$class->SUPER::new(@_);
#}

# rotate image by its orientation.
sub rotate_by_orientation {
	my ($self, $orientation) = @_;

	# if orietation is 1, there is no need for rotation.
	return if($orientation eq "1" || !$orientation);

	my $degree = _rotation_by_orientation($orientation);

	$self->rotate($degree);

#	if(_needs_flip($orientation)) {
#		$self->flip_horizotal;
#	}
}

# detect image's orientation.
sub detect_orientation {
	my ($class, $filename) = @_;

	my $exif = Exif::Simple->new($filename);

	return unless $exif;

	$exif->orientation;
}

# Rotation degree table for image orientaion.
my $orientaion_table = {
	"1" => 0,
	"2" => 0,
	"3" => 180,
	"4" => 180,
	"5" => 90,
	"6" => 90,
	"7" => 270,
	"8" => 270,
};

# calculate rotation deggree from Exif orientation value.
sub _rotation_by_orientation {
	my $orientation = shift;
	
	$orientaion_table->{$orientation};
}

# detect whether the picture needs flipping or not.
sub _needs_flip {
	my $orientation = shift;

	if($orientation eq "2" or $orientation eq "4" 
	   or $orientation eq "5" or $orientation eq "7") {
		return 1;
	}

	0;
}

1;
=pod
package MTCMS::Image::ImageMagick;

@MTCMS::Image::ImageMagick::ISA = qw( MTCMS::Image MT::Image::ImageMagick );

# orverride
sub rotate_by_orientation {
	my ($image, $orientation) = @_;

    my $magick = $image->{magick};
	my $err = $magick->AutoOrient;

    return $image->error(MT->translate(
        "AutoOrient failed: [_1]", $err)) if $err;
	
    $magick->Profile("*") if $magick->can('Profile');
	
	my ($w, $h) = $magick->Get(qw(width height));
    ($image->{width}, $image->{height}) = ($w, $h);
    wantarray ? ($magick->ImageToBlob, $w, $h) : $magick->ImageToBlob;

}

# return rotated image.
sub rotate {
	my ($image, $degree) = @_;

    my $magick = $image->{magick};
	my $err = $magick->Rotate($degree);

    return $image->error(MT->translate(
        "Rotating to [_1] failed: [_2]", $degree, $err)) if $err;
	
    $magick->Profile("*") if $magick->can('Profile');
	
	my ($w, $h) = $magick->Get(qw(width height));
    ($image->{width}, $image->{height}) = ($w, $h);
    wantarray ? ($magick->ImageToBlob, $w, $h) : $magick->ImageToBlob;

}

package MTCMS::Image::GD;

@MTCMS::Image::GD::ISA = qw( MTCMS::Image MT::Image::GD );

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

package MTCMS::Image::NetPBM;

@MTCMS::Image::NetPBM::ISA = qw( MTCMS::Image MT::Image::ImageMagick );


sub rotate {
	my ($image, $degree) = @_;

	return $image->error(MT->translate("Image rotation with NetPBM is currently not supported."));
}
=cut
1;

=head1 NAME 

MTCMS::Image MT::Image extention for MTCMS

=head SYNOPSIS
	
	use MTCMS::Image;
    my $img = MT::Image->new( Filename => '/path/to/image.jpg' );
    my($blob, $w, $h) = $img->fix_orientation;

=head1 DESCRIPTION

MTCMS::Image is extended class of MT::Image.

Supported below:

	* Rotation.
    * Detect picture orientatin from its Exif.
	* Rotation with picture's orientation.
    * Obtain various Exif informations.
=cut

