package MailPack::Util;

use strict;
use base 'Exporter';

#21800 添付ファイルをカスタムフィールドとして登録

our @EXPORT_OK = qw( custom_fields_class custom_fields_serialize get_custom_fields_informations custom_fields_insert_html );

sub custom_fields_class { return MT->model('field'); }
sub custom_fields_serialize {
    my $fields = shift or return '';
    return '' unless 'ARRAY' eq ref $fields;
    return join ',' , map { $_->{id} } grep { $_->{check} == 1 } @$fields;
}
sub get_custom_fields_informations {
    my ( $blog_id , $cf_checked_ids , $error ) = @_;

    $cf_checked_ids ||= "";

    my $class = custom_fields_class() or return '';
    my @cf_all_ids = get_custom_fields_on_blog_and_system( $blog_id ) or return '';

    my @cf_checked_ids;
    my $checked = {};
    if ( $cf_checked_ids ) {   

        if ( "ARRAY" eq ref ( $cf_checked_ids ) ) {
           @cf_checked_ids = @$cf_checked_ids;
        }
        elsif ( "" eq ref ( $cf_checked_ids ) ) {
           @cf_checked_ids = grep { $_ =~ /^\d+$/ } split /\s*,\s*/ , $cf_checked_ids;
        }

        if ( @cf_checked_ids ) {
           $checked->{$_} = 1 for @cf_checked_ids;
           @cf_all_ids = grep { ! ( exists $checked->{$_} && $checked->{$_} ) } @cf_all_ids;
        }
    }

    my @cf;
    my $plugin = MT->component('MailPack');
    my $blog = MT::Blog->load($blog_id) || '';
    for my $id ( @cf_checked_ids , @cf_all_ids ) {

        next unless $id;
        my $field = $class->load($id);

        my $err_info = {
            no => 0,
            message => '',
            field_id => $id,
            field_name => defined $field ? $field->name : '',
            blog_id => $blog_id,
            blog_name => $blog ? $blog->name : MT->translate('Unknown blog') . " (ID:$blog_id)",
        };

        unless ( defined $field ) {

            $err_info->{no} = 1;
            $err_info->{message} = $plugin->translate(
              'Configuration information contained in custom fields (ID: [_1]) is a blog to post ([_2]) does not exist. This custom field might have been removed. Will be corrected by re-save the settings.',
               $id,
               $err_info->{blog_name}
            );
            doLog( "MailPack: " . $err_info->{message} , $blog_id );
            push @$error , $err_info if $error && 'ARRAY' eq ref($error);
            next;

        }
        unless ( $field->blog_id == 0 || $field->blog_id == $blog_id ) {

            $err_info->{no} = 2;
            $err_info->{message} = $plugin->translate(
                'Configuration information contained in the custom field ([_1]) is a blog to post ([_2]) It is not in use. Will be corrected by re-save the settings.',
                $err_info->{field_name},
                $err_info->{blog_name}
            ); 
            doLog( "MailPack: " . $err_info->{message} , $blog_id );
            push @$error , $err_info if $error && 'ARRAY' eq ref($error);
            next;

        }
        unless ( $field->type eq 'image' || $field->type eq 'file'  ) {

            $err_info->{no} = 3;
            $err_info->{message} = $plugin->translate(
                'Configuration information contained in the blog to post ([_2]) Custom Fields ([_1]) is fit for the type of attachment that can not be used for registration. Will be corrected by re-save the settings.',
                $err_info->{field_name},
                $err_info->{blog_name}
            ); 
            doLog( "MailPack: " . $err_info->{message} , $blog_id );
            push @$error , $err_info if $error && 'ARRAY' eq ref($error);
            next;

        }
        unless ( $field->obj_type eq 'entry' ) {

            $err_info->{no} = 4;
            $err_info->{message} = $plugin->translate(
                'Configuration information contained in the blog to post ([_2]) Custom Fields ([_1]) is a blog post is not available. Will be corrected by re-save the settings.',
                $err_info->{field_name},
                $err_info->{blog_name}
            ); 
            doLog( "MailPack: " . $err_info->{message} , $blog_id );
            push @$error , $err_info if $error && 'ARRAY' eq ref($error);
            next;

        }

        my %data = (
           id    => $field->id,
           name  => $field->name,
           basename => $field->basename,
           type  => $field->type,
           required => $field->required,
           desc  => $field->description,
           check => exists $checked->{$id} && $checked->{$id} ? 1 : 0,
        );
        push @cf , \%data;


    }
    return \@cf if @cf;
    return '';
}
sub get_custom_fields_on_blog_and_system {
    my $blog_id = shift;

    my $class = custom_fields_class() or return '';
    my $fields = $class->load_iter({
          blog_id   => [ 0 , $blog_id ],
          obj_type  => 'entry',
          type      => ['image','file'],
       },{
          'sort'    => 'id',
          direction => 'ascend',
    }) or return '';

    my @cf;
    while ( my $field = $fields->()  ) {
       push @cf , $field->id;
    }
    return wantarray ? @cf : \@cf;
}
sub custom_fields_insert_html { 
    my ( $asset ) = @_;
    my $param = { enclose => 1 };
    my $html =  $asset->as_html( $param ); 

    # callback for rewriting image embbeded html.
    MT->run_callbacks('Mailpack::asset_html', $asset, \$html);

    return $html;
}

sub doLog {
    my ( $msg , $blog_id ) = @_;

    require MT::Log;
    my $log = MT::Log->new;
    $log->message( $msg );
    $log->level(MT::Log::ERROR());
    $log->blog_id( $blog_id );
    $log->class('MailPack');
    $log->save or die $log->errstr;
}

1;
