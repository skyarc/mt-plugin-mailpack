use strict;
use Carp;
use Fcntl qw( :DEFAULT :flock );

package Exif::Simple;

use base qw (Class::Accessor::Fast);
 
# define Exif tags in 'tag' => name
my %taget_tag = (
    '270' => 'imageDescription',
    '271' => 'make',
    '272' => 'model',
    '274' => 'orientation',
    '306' => 'dateTime',
    '315' => 'artist',
    '33432' => 'copyright',
    '33434' => 'exposureTime',
    '33437' => 'fNumber',
    '37386' => 'focalLength',
    '37396' => 'subjectArea',
#    '37500' => 'makerNote',
    '37510' => 'userComment',
    '41986' => 'exposureMode',
    '41987' => 'whiteBalance',
    '41988' => 'digitalZoomRatio',
    '41989' => 'focalLengthIn35mmFilm',
    '41990' => 'sceneCaptureType',
    '41991' => 'gainControl',
    '41992' => 'contrast',
    '41993' => 'saturation',
    '41994' => 'sharpness',
);

my @ACCESSORS = (
	values(%taget_tag),
	qw(fld_marker tiff_size comment),
);


__PACKAGE__->mk_accessors(@ACCESSORS);

# Construct and Parse
sub new {
    my ($class, $file) = @_;

    $file or return;

    my $self = {
	'file' => $file,
    };
    bless $self, $class;

    # parse exif
    $self->parse($file)
		or return;

	$self;
}

# parse file.
sub parse {
    my ($self, $input_file) = @_;    

# open file and read it
	my $fh;
    sysopen($fh, $input_file, Fcntl::O_RDONLY) or  warn "Can't open $input_file: $!" and return;
    binmode($fh);

    my $status = $self->parse_image($fh);

    close($fh);

    $status;
}

# parse image
sub parse_image {
    my ($self, $fh) = @_;

    my $tmp;
    read($fh, $tmp, 2);
    return unless(unpack("H4", $tmp) eq 'ffd8'); #is JPEG
#  parse tiff tags.
    while(1){
	read($fh, $tmp, 2);
	my $fld_marker = unpack("H4", $tmp);
        $self->fld_marker($fld_marker);

	read($fh, $tmp, 2);
	my $tiff_size = unpack("n", $tmp);
	$self->tiff_size($tiff_size);

	if($fld_marker eq 'ffe1'){
	    read($fh, $tmp, 6);
	    my $magic = unpack("A6", $tmp);
	    if($magic eq "Exif"){
		read($fh, $tmp, $tiff_size - 8); # as global buffer variable
		$self->read_tiff(\$tmp);
	    }else{
		read($fh, $tmp, $tiff_size - 8); #dummy
	    }
	}elsif($fld_marker eq 'fffe'){
	    read($fh, $tmp, $tiff_size - 2); #dummy
	    $self->read_comment(\$tmp);
	}elsif($fld_marker eq 'ffda' or $fld_marker eq ''){
	    # terminate if there is no tag or SOS found. 
	    last;
	}else{
	    read($fh, $tmp, $tiff_size - 2); #dummy
	}
    }

    1;
}

# Exif parser routines.

# parse tiff header
sub read_tiff{
    my ($self, $buf_ref) = @_;

    my($byte_order, $offset, $iifd);

    my ($long_tmpl, $short_tmpl);
    $byte_order = unpack("A2", substr($$buf_ref, 0, 2));
    if($byte_order eq "II"){
	($long_tmpl, $short_tmpl) = ("V", "v"); # Big endian  
    }elsif($byte_order eq "MM"){
	($long_tmpl, $short_tmpl) = ("N", "n"); # Litte endian
    }else{
	die "Incorrect byte order:$byte_order :$!";
    }

    $offset = unpack($long_tmpl, substr($$buf_ref, 4, 4));
    1 while($offset = $self->read_ifd(\$short_tmpl, \$long_tmpl, $buf_ref, $offset, 0));
}

# parse IFD
sub read_ifd{
	my($self, $short_tmpl_ref, $long_tmpl_ref, $buf_ref, $offset, $parent_tag_id) = @_;
	my($num_dir_entry) = unpack($$short_tmpl_ref, substr($$buf_ref, $offset, 2));
	my($next_offset) = unpack($$long_tmpl_ref, substr($$buf_ref, $offset + 2 + $num_dir_entry * 12, 4));
	$offset += 2;
	while($num_dir_entry){
		$self->read_dir_entry($short_tmpl_ref, $long_tmpl_ref, $buf_ref,  substr($$buf_ref, $offset, 12), --$num_dir_entry, $parent_tag_id);
		$offset += 12;
	}

	$next_offset;
}

# parse dirctory entry
sub read_dir_entry{
	my($self, $short_tmpl_ref, $long_tmpl_ref, $buf_ref, $dir_entry, $num_dir_entry, $parent_tag_id) = @_;


	my($tag, $type, $num_data, $dir_offset)
           = unpack($$short_tmpl_ref . $$short_tmpl_ref . $$long_tmpl_ref .  $$long_tmpl_ref, $dir_entry);
	my $data_value = '';
	my($dir_size) = (1, 1, 2, 4, 8)[$type-1] || 1;

 #       print 'buf len : ' . length($$buf_ref) . "\n";
 #       print 'num data : ' . $num_data . "\n";

	if($tag==34665 || $tag==34853 || $tag==40965){
		1 while $dir_offset = $self->read_ifd($short_tmpl_ref, $long_tmpl_ref, $buf_ref, $dir_offset, 0);
	}elsif($taget_tag{$tag}){
		#userCommentは、文字列と想定して出力
		$type = 2 if($taget_tag{$tag} eq 'userComment'); 
		if($num_data * $dir_size > 4){
			foreach my $i (0 .. $num_data - 1){
#			    print ( $dir_offset + $i * $dir_size . " : " .  $dir_size . "\n");
				$data_value .= $self->read_data($short_tmpl_ref, $long_tmpl_ref, $type, substr($$buf_ref, $dir_offset + $i * $dir_size, $dir_size));
			}
		}else{
			foreach my $i (0 .. $num_data - 1){
				$data_value .= $self->read_data($short_tmpl_ref, $long_tmpl_ref, $type, substr($dir_entry, 8 + $i * $dir_size, $dir_size));
			}
		}
		
#		print "$taget_tag{$tag}:$data_value";

                my $tag_name = $taget_tag{$tag};
                unless ( $tag == 274 && exists $self->{$tag_name} ) {
                    $self->set($tag_name, $data_value);
                }
	}
}

# データタイプに応じたデコード
sub read_data{
	my ($this, $short_tmpl_ref, $long_tmpl_ref, $type, $data) = @_;
	if ($type==1){
		return unpack("C", $data);
	}elsif($type==2){
		return unpack("A", $data);
	}elsif($type==3){
		return unpack($$short_tmpl_ref, $data);
	}elsif($type==4){
		return unpack($$long_tmpl_ref, $data);
	}elsif($type==5){
		return join("/", unpack($$long_tmpl_ref . $$long_tmpl_ref, $data));
	}else{
		return unpack("H*", $data); #分からない形式はとりあえず16進で
	}
}

# コメントフィールド
sub read_comment{
	my ($self, $comment_data) = @_;
	#とりあえずどんなコメントでもそのまま出力
	$self->comment($comment_data);
}

1;
