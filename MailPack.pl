package MT::Plugin::MailPack;

use strict;
use warnings;
use MT 5;
use MT::Blog;
use MT::Author;
use MT::Plugin;
use MT::Template::Context;
use MT::Mailpackaddress;
#use quemgr qw(quemgr);
use vars qw( $PLUGIN_NAME $VERSION $SCHEMA_VERSION );

$PLUGIN_NAME = 'MailPack';
$VERSION = '2.100';
$SCHEMA_VERSION = '1.059';

eval {
    require HTML::Parser;
    HTML::Parser->import;
};

my $has_loading_error;
if ($@ ) {
    $has_loading_error = 1;
}

my $description = $@ ?
    q{<p style="color: #f39800;"><__trans phrase="* HTML::Parser is required."></p>} :
    q{<__trans phrase='A Movable Type plugin to post enties via e-mail.'>};

use base qw(MT::Plugin);
my $plugin = __PACKAGE__->new({
    id => $PLUGIN_NAME,
    key => $PLUGIN_NAME,
    name => $PLUGIN_NAME,
    version => $VERSION,
    doc_link => 'http://www.skyarc.co.jp/product/manual/mailpack/',
    author_name => 'SKYARC System Co., Ltd,',
    author_link => 'http://www.skyarc.co.jp/',
    l10n_class => 'MailPack::L10N',
    schema_version => $SCHEMA_VERSION,
    config_template => 'notification.tmpl',
    settings => new MT::PluginSettings([
        ['notification_flg', { Default => 1 }],
        ['notification_superuser', { Default => 0 }],
        ['notification_subject', { Default => 'MailPack:' }],
        ['thumbnail_width', { Default => 200 }],
        ['insert_point', { Default => 1 }],
        ['comment_thread', { Default => 0 }],
        ['post_status' , { Default => 1 }],
        ['assist_post_status' , { Default => 1 }],
    ]),
    description => $description,
});
MT->add_plugin($plugin);

#----- Task
sub init_registry {
    my $plugin = shift;

    return '' if $has_loading_error;

    $plugin->registry({
        object_types => {
            'Mailpackaddress' =>  'MT::Mailpackaddress',
            'MailPack_MessageId' => 'MT::MailPack::MessageId',
        },
        tasks => {
            'MailPackTask' => {
                label       => 'MailPack Check to Posted Mails',
                frequency   => 10, # seconds
                code        => sub { check_mails( $plugin ); },
            },
        },
        callbacks => {
            'cms_save_permission_filter.Mailpackaddress'      => sub {0},
            'cms_delete_permission_filter.Mailpackaddress'    => sub {0},
            'cms_view_permission_filter.Mailpackaddress'      => sub {0},
            'cms_save_permission_filter.MailPack_MessageId'   => sub {0},
            'cms_delete_permission_filter.MailPack_MessageId' => sub {0},
            'cms_view_permission_filter.MailPack_MessageId'   => sub {0},
            $MT::VERSION < 6 
            ? ( 
                'cms_upload_file.image' => '$MailPack::MailPack::CMS::cb_exif_clear',
                'api_upload_image' => '$MailPack::MailPack::CMS::cb_exif_clear', 
            ) : (
                'template_param.asset_upload' => '$MailPack::MailPack::CMS::cb_tmpl_param_asset_upload',
                'template_param.asset_list' => '$MailPack::MailPack::CMS::cb_tmpl_param_asset_upload',
                'template_param.file_upload' => '$MailPack::MailPack::CMS::cb_tmpl_param_asset_upload',
            ),
        },
        listing_screens => {
            'mailpack' => {
                 object_type => 'Mailpackaddress',
                 object_label => 'MailPack Configure',
                 object_label_plural => 'MailPack Configure',
                 default_sort_key => [ 'email' , 'created_on' ],
                 permission => 'administer',
                 scope_mode => 'wide',
                 screen_label => 'MailPack Configure Manage',
                 view => [ 'blog' , 'website' , 'system' ],
                 primary => [ 'mailaddress' ],
            },
        },
        list_properties => {
            'mailpack' => {
                 mailaddress => {
                     label => 'MailPack MailAddress',
                     base => '__virtual.string',
                     display => 'force',
                     order => 100,
                     html => sub {
                        my $prop = shift;
                        my ( $obj , $app , $opts ) = @_;
                        my $link = $app->uri(
                           mode => 'edit',
                           args => {
                              _type => 'mailpack',
                              blog_id => $app->blog ? $app->blog->id : 0 ,
                              setting_id => $obj->setting_id,
                              magic_token => $app->current_magic
                        });
                        return sprintf '<a href="%s">%s</a>' , $link , $obj->email;
                     },
                 },
                 email => {
                     auto => 1,
                     display => 'none',
                 },
                 blog_name => {
                     label => 'MailPack Blog',
                     base  => '__common.blog_name',
                     display => 'default',
                     order => '200',
                 },
                 category => {
                     label => 'MailPack Category',
                     base => '__virtual.string',
                     display => 'force',
                     order => 400,
                     raw => sub {
                        my $prop = shift;
                        my ( $obj , $app , $opts ) = @_;
                        my $category_id = $obj->category_id or return '-';
                        my $category = MT::Category->load($category_id) or return '-';
                        return $category->label;
                     },
                 },
                 created_on => {
                    auto => 1,
                    label => 'MailPack Created On', 
                    use_future => 1,
                    display => 'force',
                    order => 500,
                 },
                 author => {
                     label => 'MailPack Author',
                     base => '__virtual.string',
                     display => 'force',
                     order => 25200,
                     raw => sub {
                        my $prop = shift;
                        my ( $obj , $app , $opts ) = @_;
                        my $author_id = $obj->author_id or return '-';
                        my $author = MT::Author->load( $author_id ) or return '-';
                        return $author->name;
                     },
                 },
            },
        },
        'content_actions' => {
            'mailpack' => {
                'edit_mailpack' => {
                    class => 'icon-action',
                    label => 'Add Entry Email Setting',
                    mode  => 'edit_mailpack',
                    order => 100,
                    permission => 'administer',
                },
            },
        },
        list_actions => {
            'mailpack' => {
                'delete' => {
                   label      => 'Delete',
                   mode       => 'delete_mailpack',
                   order      => 110,
                   js_message => 'delete',
                   button     => 1,
                   permission => 'administer',
                },
            },
        },
        applications => {
            cms => {
                methods => {
                    edit_mailpack   => '$MailPack::MailPack::CMS::edit',
                    delete_mailpack => '$MailPack::MailPack::CMS::delete',
                    save_mailpack   => '$MailPack::MailPack::CMS::post',
                },
                menus => {
                    'entry:mailpack' => {
                        label => 'MailPack Configure',
                        mode => 'list',
                        args => { _type => 'mailpack' },
                        order => 99999,
                        permission => 'administer',
                        view => [ 'blog' , 'website' , 'system' ],
                    },
                },
            },
        },
    });
}

sub instance { $plugin }

sub check_mails {
    my $plugin = shift;
    require quemgr;
    quemgr::quemgr($plugin);
    1;
}

# Remove mapped object in MT::Mailpackaddress
MT::Blog->add_callback ('pre_remove', 5, $plugin, \&_hdlr_pre_remove);
MT::Author->add_callback ('pre_remove', 5, $plugin, \&_hdlr_pre_remove);
sub _hdlr_pre_remove {
    my ($cb, $obj) = @_;
    my %term;
    if ($obj->isa('MT::Blog')) {
        $term{blog_id} = $obj->id;
    }
    elsif ($obj->isa('MT::Author')) {
        $term{author_id} = $obj->id;
    }
    else {
        return 1;
    }
    map { $_->remove } MT::Mailpackaddress->load (\%term);
}

## 受信したメールを一時的に保存するディレクトリ
sub tmpdir {

    my $cfg = MT->config;
    my $mailpack_tempdir = $cfg->MailPackTempDir;
    if ( defined $mailpack_tempdir && $mailpack_tempdir )
    {
        return $mailpack_tempdir;
    }
    my $temp_dir = $cfg->TempDir;
    my $mt_dir   = MT->instance->{mt_dir};
    $mt_dir =~ s/[^A-Za-z0-9]+/_/g;

    my $dir = sprintf "%s_%s", $plugin->id, $mt_dir;

    require File::Spec;
    $temp_dir = File::Spec->catdir($temp_dir, $dir);

    return $temp_dir;

}

1;
__END__
