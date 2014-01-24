use strict;

use Exif::Simple;
use Test::More tests => 16;
use Data::Dumper;

my $exif;

# ensure orientaion of orientation1.jpg is 1
my $exif = Exif::Simple->new('t/orientation1.jpg');
#print Dumper($exif);

is($exif->orientation, 1, 'orientation is 1');
is($exif->fNumber, '40/10', 'f number is 4(40/10)');
is($exif->model,   'DMC-GF2', 'model is DMC-GF2');
is($exif->dateTime, '2010:12:1415:09:58', 'shot date is 2010:12:1415:09:58');
is($exif->make , 'Panasonic', 'maker is Panasonic');
is($exif->focalLength, '140/10', 'focal length is 140/10');

# ensure orientaion of orientation6.jpg is 6 
$exif = Exif::Simple->new('t/orientation6.jpg');

#print Dumper($exif);
is($exif->orientation, 6, 'oriatation is 6');
is($exif->fNumber, '56/10', 'f number is 4(56/10)');
is($exif->model,   'DMC-GF2', 'model is DMC-GF2');
is($exif->dateTime, '2010:12:1414:06:11', 'shot date is 2010:12:1414:06:11');
is($exif->make , 'Panasonic', 'maker is Panasonic');
is($exif->focalLength, '140/10', 'focal length is 140/10');

# ensure orientaion of orientation3.jpg is 3
my $exif = Exif::Simple->new('t/orientation3.jpg');
#print Dumper($exif);

is($exif->orientation, 3, 'orientation is 3');

# ensure orientaion of orientation8.jpg is 8
my $exif = Exif::Simple->new('t/orientation8.jpg');
#print Dumper($exif);

is($exif->orientation, 8, 'orientation is 8');

# test no file.
$exif = Exif::Simple->new('t/not_exist.jpg');
is($exif, undef, 'no image');

# no JPEG Image.
$exif = Exif::Simple->new('t/t_exif_simple.pl');
is($exif, undef, 'not image');


