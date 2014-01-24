package MIME::KbParser;

use MIME::Parser;
@ISA = qw(MIME::Parser);
use Encode;
use MT::Util qw( encode_url );

sub output_path {
    my ($self, $head) = @_;
    my $dir = $self->filer->output_dir($head);
    my $fname = $head->recommended_filename;

    ### Can we use it:
    if (!defined( $fname ) || $self->filer->ignore_filename ) {
        $fname = $self->filer->output_filename($head);
    }elsif ($self->filer->ignore_filename) {
        $fname = $self->filer->output_filename($head);
    }
    $fname =~ s/^\s+|\s+$//g;

    ## Perl version 5.8.8
	# detect mime header.
    if( $fname =~ m/^=\?.+\?[QB]\?/i ){
        $fname = Encode::decode('MIME-Header', $fname );
        $fname = encode_url( $fname );
    }
    elsif ($fname =~ /\x1b/) {
        $fname = Encode::decode('iso-2022-jp', $fname);
    }

    return $self->filer->find_unused_path($dir, $fname);
}

1;

