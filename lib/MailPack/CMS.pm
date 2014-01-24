package MailPack::CMS;

use strict;
use warnings;
use Exporter;
use MT::App;
use MT::Blog;
use MT::Author;
use MT::Category;
use MT::Mailpackaddress;
use MT::Log;
use MT::Util;
use MT::Plugin;
use Data::Dumper;
use MailPack::Util qw( custom_fields_serialize get_custom_fields_informations );

use base qw( MT::App );

sub plugin {
    return MT->component('MailPack');
}

sub _permission_check {
    my $app = MT->instance;
    return ($app->user && $app->user->is_superuser);
}

sub edit {
    my $plugin = MT::Plugin::MailPack->instance;
    my ($app) = @_;

    # システム管理者チェック
    return $app->return_to_dashboard(permission => 1)
        unless _permission_check();

    # 設定値取得
    my $q = $app->{query};
    # パラメータ名全取得
    my @p_name = $q->param();

    my $blog_id = $app->blog ? $app->blog->id : 0;

    my @blogs = MT::Blog->load;

    # 各パラメータ初期化
    my @bc_list;

    my $err_msg = $q->param('err_msg') || undef;
    my $setting_id  = "";
    my $setting_blog_id = 0;
    my $setting_email = "";
    my $setting_pop3  = "";
    my $setting_user  = "";
    my $setting_pass  = "";
    my $setting_port  = "";
    my $setting_ssl_flg = 0;
    my $setting_filter_type = 0;
    my $setting_assist_id = 0;
    my @setting_category_ids;
    my $setting_cf_ids = "";
    my @buf_category;
    my %param;
    my @cf_error;  #カスタムフィールドのエラー表示用

    if (defined ( $err_msg ) && $err_msg ) {
        if ($err_msg eq 'email_err'){
            $err_msg = $plugin->translate('email address repetition');
        }elsif ($err_msg eq 'conect_err'){
            $err_msg = $plugin->translate('email server no attestation. please setting again');
        }elsif ($err_msg eq 'user_err'){
            $err_msg = $plugin->translate('email user repetition. please setting again');
        }else{
            if ( $err_msg =~ /\t/ ) {
               my @err = map { $plugin->translate( $_ ) } split( /\t/ , $err_msg);
               $err_msg = join "\n\n" , @err;
            }
            else {
               $err_msg = $plugin->translate($err_msg);
            }
        }

       # パラメータ取得
       $setting_id      = $q->param('setting_id');
       $setting_blog_id = $q->param('blog_select') || 0;
       $setting_email   = $q->param('u_d_address_text');
       $setting_pop3    = $q->param('u_d_pop3_text');
       $setting_user    = $q->param('u_d_user_text');
       $setting_pass    = $q->param('u_d_pass_text');
       $setting_port    = $q->param('u_d_port_text') || "110";
       $setting_ssl_flg = $q->param('u_d_ssl_flg') || "0";
       $setting_filter_type = $setting_blog_id
          ? $q->param('u_d_filter_type') || 0
          : 0;
       $setting_assist_id  = $setting_blog_id && $setting_filter_type
          ? $q->param('u_d_assist_id_' . $setting_blog_id ) || 0
          : 0;

       my @cf_ids = $q->param('custom_fields_' . $setting_blog_id );
       if ( @cf_ids ) {
            $setting_cf_ids = join ',' , grep { /^\d+$/ } @cf_ids;
       }

        # パラメータ名全取得
        my @params = $q->param();
        my $selected_cat = {};
        for ( @params ) {
           $selected_cat->{$1} = $1 if $_ =~ m|^category_(\d+)$|i;
        }
        my @cats = MT::Category->load({ blog_id => $setting_blog_id });
        for my $cat ( @cats ) {
            my $flag = exists $selected_cat->{$cat->id} && $selected_cat->{$cat->id} ? 1 : 0;
            push @buf_category , {
                C_ID    => $cat->id,
                C_LABEL => $cat->label,
                C_FLUG  => $flag,
            };
        }
    }
    # 投稿先メールアドレス設定をロード
    elsif ($q->param('setting_id') ne "") {
        my @settings = MT::Mailpackaddress->load({setting_id=>$q->param('setting_id')});
        my $set_address = shift(@settings);
        unless ($set_address){
            return $app->error($plugin->translate( 'edit data not find' ));
        }
        my @cat1 = MT::Category->load({blog_id => $set_address->blog_id});
        my @cat2 = MT::Mailpackaddress->load({email => $set_address->email});
        foreach my $cat1 (@cat1) {
            my $c_clug = 0;
            foreach my $cat2 (@cat2) { if ($cat1->id == $cat2->category_id)  { $c_clug = 1; last; } }
            my $buf_hash2 = {
                C_ID => $cat1->id,
                C_LABEL => $cat1->label,
                C_FLUG => $c_clug
            };
            push(@buf_category,$buf_hash2);
        }

        $setting_id       = $set_address->setting_id;
        $setting_blog_id  = $set_address->blog_id;
        $setting_email    = $set_address->email;
        $setting_pop3     = $set_address->pop3;
        $setting_user     = $set_address->user;
        $setting_pass     = $set_address->pass;
        $setting_port     = $set_address->port;
        $setting_ssl_flg  = $set_address->ssl_flg;
        $setting_filter_type = $set_address->filter_type || 0;
        $setting_assist_id   = $set_address->assist_id || 0;
        $setting_cf_ids   = $set_address->cf_ids || '';

    }

    # 設定元のブログ-カテゴリの全ハッシュ(新規入力箇所)
    my @authors = MT::Author->load;
    foreach my $blog (@blogs) {
        my $select_blog_flg = 0;
        my @c_list;
        my @u_list;
        if ($setting_blog_id == $blog->id){
            $select_blog_flg = 1;
        }
        @c_list = &_get_sub_category_list(0, $blog->id, 0);
        my @buf_list;
        if ($select_blog_flg == 1){
            foreach my $c_list (@c_list) {
                $c_list->{C_SELECT} = 0;
                foreach my $select_category (@buf_category) {
                    if (($c_list->{C_ID} == $select_category->{C_ID}) && ($select_category->{C_FLUG} == 1)){
                        $c_list->{C_SELECT} = 1;
                        last;
                    }
                }
                push(@buf_list, $c_list);
            }
            @c_list = @buf_list;
        }

        foreach my $author ( @authors ) 
        {
            next unless $author->is_superuser 
                 || $author->permissions($blog->id)->can_post;

            push @u_list , {
                A_ID => $author->id,
                A_NAME => $author->nickname,
                A_SELECTED => $author->id == $setting_assist_id ? 1 : 0,
            };
        }
        my $cf_on_blog;
        $cf_on_blog = get_custom_fields_informations( $blog->id , $select_blog_flg ? $setting_cf_ids : '' , \@cf_error );
        my $buf_hash1 = {
            B_ID => $blog->id,
            B_NAME => $blog->name,
            B_SELECT => $select_blog_flg,
            C_ARRAY => \@c_list,
            CUSTOM_FIELDS => $cf_on_blog,
            AUTHORS => scalar @u_list ? \@u_list : 0,
            ASSIST_ID => $setting_assist_id,
        };
        push(@bc_list,$buf_hash1);
    }

    $param{page_title}    = $plugin->translate('Add Entry Email Setting');
    $param{mpack_error}   = $err_msg;
    $param{mpack_saved}   = $q->param('saved') ? 1 : 0;

    $param{B_C_LIST} = \@bc_list;
    $param{APP_URL}  = $app->mt_uri;

    $param{CF_ERROR} = @cf_error ? \@cf_error : '';

    $param{SETTING_FILTER_TYPE} = $setting_filter_type;
    $param{SETTING_FILTER_TYPE_0} = $setting_filter_type == 0;
    $param{SETTING_FILTER_TYPE_1} = $setting_filter_type == 1;
    $param{SETTING_FILTER_TYPE_2} = $setting_filter_type == 2;

    $param{SETTING_ID}      = $setting_id;
    $param{SETTING_BLOG_ID} = $setting_blog_id;
    $param{SETTING_EMAIL}   = $setting_email;
    $param{SETTING_POP3}    = $setting_pop3;
    $param{SETTING_USER}    = $setting_user;
    $param{SETTING_PASS}    = $setting_pass;
    $param{SETTING_PORT}    = $setting_port;
    $param{SETTING_SSL_FLG} = $setting_ssl_flg;
    $param{screen_group} = 'entry';

    my $tmpl = $plugin->load_tmpl('mailpack_edit.tmpl');
    return $app->build_page($tmpl, \%param);
}

sub error_foward {
    my ( $app , $err_msg , $param) = @_;
    my $q = {};
    $q->{setting_id} = $param->{setting_id};
    $q->{blog_id} = $app->blog ? $app->blog->id : 0;
    $q->{blog_select} = $param->{blog_id};
    $q->{u_d_address_text} = $param->{email};
    $q->{u_d_pop3_text} = $param->{pop3};
    $q->{u_d_user_text} = $param->{user};
    $q->{u_d_pass_text} = $param->{pass};
    $q->{u_d_port_text} = $param->{port};
    $q->{u_d_ssl_flg} = $param->{ssl_flg} ? 1 : 0;
    $q->{u_d_filter_type} = $param->{filter_type};
    $q->{err_msg} = $err_msg;
    $q->{'u_d_assist_id_' . $param->{blog_id}} = $param->{assist_id};

    if ( exists $param->{'custom_fields_' . $param->{blog_id}} ) {
       $q->{'custom_fields_' . $param->{blog_id} } = $param->{'custom_fields_' . $param->{blog_id}};
    }

    my @params = $app->param();
    for ( @params ) {
       next if $_ =~ m!(category_)!i; 
       $app->delete_param($_);
    }
    for my $key ( keys %$q ) {
       if ( 'ARRAY' eq ref ( $q->{$key} ) ) {
          $app->param($key , ( @{ $q->{$key} } ) );
          next;
       }
       $app->param($key , $q->{$key} );
    }
    return $app->forward( 'edit_mailpack' , { err_msg => $err_msg , magic_token => $app->current_magic } );
}

sub post {
    my $plugin = MT::Plugin::MailPack->instance;
    my ($app) = @_;

    $app->validate_magic() or return;

    # システム管理者チェック
    return $app->return_to_dashboard(permission => 1)
        unless _permission_check();

    my $author_id = $app->user->id;

    # 設定値取得
    my $q = $app->{query};

    # パラメータ取得
    my $param = {};
    $param->{blog_id} = $q->param('blog_select');
    $param->{setting_id} = $q->param('setting_id');
    $param->{setting_id} = '' unless defined( $param->{setting_id} );
    $param->{email} = $q->param('u_d_address_text');
    $param->{pop3} = $q->param('u_d_pop3_text');
    $param->{user} = $q->param('u_d_user_text');
    $param->{pass} = $q->param('u_d_pass_text');
    $param->{port} = $q->param('u_d_port_text');
    $param->{ssl_flg} = $q->param('u_d_ssl_flg');
    $param->{filter_type} = $param->{blog_id}
          ? $q->param('u_d_filter_type') || 0
          : 0;
    $param->{assist_id} = $param->{blog_id} && $param->{filter_type}
          ? $q->param('u_d_assist_id_' . $param->{blog_id} ) || 0
          : 0;
    my @fields = $q->param('custom_fields_' . $param->{blog_id});
    $param->{'custom_fields_' . $param->{blog_id} } = \@fields;

    my $blog_id = $app->blog ? $app->blog->id : 0;

    # パラメータ名全取得
    my @p_name = $q->param();
    my @category_ids = ();
    foreach (@p_name) {
        if ($_ =~ m!(category_)!i) { 
            push(@category_ids, $q->param($_));
        }
    }
    
    my $cf = get_custom_fields_informations( $param->{blog_id} , \@fields );    
    my $cf_ids = '';
    $cf_ids = custom_fields_serialize( $cf ); 

    # POP server connect check
    if ($param->{ssl_flg} == 1){
        my @require_error;
        eval{require Mail::POP3Client;};
        push @require_error , 'POP over SSL need Mail::POP3Client' if $@;
        eval{require IO::Socket::SSL;};
        push @require_error , 'POP over SSL need IO::Socket::SSL' if $@;
        eval{require IO::Stringy;};
        push @require_error , 'POP over SSL need IO::Stringy' if $@; 
        eval{require Net::SSLeay;};
        push @require_error , 'POP over SSL need Net::SSLeay' if $@;
        if (scalar @require_error) {
            my $require_error = join "\t" , @require_error;
            return error_foward( $app  , $require_error , $param );
        }
        my $pop = Mail::POP3Client->new(
            HOST => $param->{pop3},
            USER => $param->{user},
            PASSWORD => $param->{pass},
            USESSL => 1,
            PORT => $param->{port},
            TIMEOUT => 30,
        );
        my $checklogin = $pop->connect() || '';
        $pop->close();
        return error_foward( $app, 'conect_err' , $param ) unless $checklogin;
    }
    else {

        eval{ require Net::POP3; };
        return error_foward( $app, 'POP need Net::POP3' , $param ) if $@;

        # POP server connect check
        my $pop = Net::POP3->new($param->{pop3}, Timeout=> 30 );
        return error_foward( $app, 'conect_err', $param ) unless $pop;

        my $checklogin = $pop->login($param->{user}, $param->{pass});
        $pop->quit;
        return error_foward( $app, 'conect_err', $param ) unless $checklogin;

    }

    my $created_on;
    my @settings = MT::Mailpackaddress->load();
    for my $setting (@settings) {
        if ($param->{setting_id} ne ""){
            if (($setting->setting_id != $param->{setting_id}) && ($setting->email eq $param->{email})){
                return error_foward( $app, 'email_err', $param );
            }
            if (($setting->setting_id != $param->{setting_id}) && ($param->{pop3} eq $setting->pop3) && ($param->{user} eq $setting->user)){
                return error_foward( $app, 'user_err', $param );
            }
            $created_on = $setting->created_on if $param->{setting_id} == $setting->setting_id;
        }else{
            if ( $param->{email} eq $setting->email ){
                return error_foward( $app, 'email_err', $param );
            }
            if (($param->{pop3} eq $setting->pop3) && ($param->{user} eq $setting->user)){
                return error_foward( $app, 'user_err', $param );
            }
        }
    }
    if ($param->{setting_id} ne ""){
        # 一旦登録してある情報を削除する
        @settings = MT::Mailpackaddress->load({ setting_id => $param->{setting_id} });
        $_->remove for @settings;
    }
    else{
        my @buf_obj = MT::Mailpackaddress->load();
        $param->{setting_id} ||= 0;
        foreach (@buf_obj) {
            if ($param->{setting_id} <= $_->setting_id) { $param->{setting_id} = $_->setting_id; $param->{setting_id}++; }
        }
    }

    my @ts = MT::Util::offset_time_list(time, $param->{blog_id});
    my $modified_on = sprintf '%04d%02d%02d%02d%02d%02d', $ts[5]+1900, $ts[4]+1, @ts[3,2,1,0];
    unless ($created_on){
        $created_on = $modified_on;
    }

    unless (@category_ids){
        my $set_mail = MT::Mailpackaddress->new;
        $set_mail->setting_id($param->{setting_id});
        $set_mail->blog_id($param->{blog_id});
        $set_mail->email($param->{email});
        $set_mail->pop3($param->{pop3});
        $set_mail->user($param->{user});
        $set_mail->pass($param->{pass});
        $set_mail->port($param->{port});
        $set_mail->ssl_flg($param->{ssl_flg} || 0);
        $set_mail->category_id(undef);
        $set_mail->author_id($author_id);
#        $set_mail->modified_on($modified_on);
        $set_mail->created_on($created_on);
        $set_mail->filter_type( $param->{filter_type});
        $set_mail->assist_id( $param->{assist_id});
        $set_mail->cf_ids( $cf_ids );
        $set_mail->save
           or die $set_mail->errstr;
    }
    else{
        foreach (@category_ids) {
            my $set_mail = MT::Mailpackaddress->new;
            $set_mail->setting_id($param->{setting_id});
            $set_mail->blog_id($param->{blog_id});
            $set_mail->email($param->{email});
            $set_mail->pop3($param->{pop3});
            $set_mail->user($param->{user});
            $set_mail->pass($param->{pass});
            $set_mail->port($param->{port});
            $set_mail->ssl_flg($param->{ssl_flg} || 0);
            $set_mail->category_id($_);
            $set_mail->author_id($author_id);
#            $set_mail->modified_on($modified_on);
            $set_mail->created_on($created_on);
            $set_mail->filter_type( $param->{filter_type});
            $set_mail->assist_id( $param->{assist_id});
            $set_mail->cf_ids( $cf_ids );
            $set_mail->save
               or die $set_mail->errstr;
       }
    }
    return $app->redirect($app->uri(
        mode => 'edit_mailpack',
        args => {
             setting_id => $param->{setting_id},
             blog_id => $blog_id,
             magic_token => $app->current_magic,
             saved => 1,
    }));
}

sub delete {
    my $plugin = MT::Plugin::MailPack->instance;
    my ($app) = @_;

    $app->validate_magic() or return;

    # システム管理者チェック
    return $app->return_to_dashboard(permission => 1)
        unless _permission_check();

    # 設定値取得
    my $q = $app->{query};
    # パラメータ名全取得
    my @p_name = $q->param();
    my @ids = $q->param('id');
    my $blog_id = $app->blog ? $app->blog->id : 0;
    foreach my $id (@ids) {
        my @settings = MT::Mailpackaddress->load({ id => $id });
        $_->remove for @settings;
    }
    return $app->redirect($app->uri(
        mode => 'list',
        args => { _type => 'mailpack' , blog_id => $blog_id }));
}

# Write Log --------------------------------------
sub writelog {
    my ($log_msg, $log_level, $log_time) = @_;

    my $log = MT::Log->new();
    $log->message ($log_msg || '');
    $log->level ($log_level || MT::Log::DEBUG());
    $log_time = time if !defined $log_time;
    my @ts = gmtime $log_time;
    my $ts = sprintf '%04d%02d%02d%02d%02d%02d', $ts[5]+1900, $ts[4]+1, @ts[3,2,1,0];
    $log->modified_on ($ts);
    $log->save
        or die $log->errstr;
}

#-------------------------------------------------

sub _get_sub_category_list {
    my ($cats, $blog_id, $level) = @_;
    my @categorys;
    my @category_list;
    my $space;
    if ($level == 0){
        @categorys = MT::Category->top_level_categories($blog_id);
    }else{
        @categorys = @$cats;
    }    
    for ( 1 .. $level ) { $space = $space . "&nbsp;"; }
    foreach my $category (@categorys) {
        my $main_hash = {
            C_ID    => $category->id,
            C_LABEL => $category->label,
            C_SPACE => $space,
            C_LEVEL => $level,
        };
        push @category_list, $main_hash;
        my @sub_cate = $category->children_categories;
        my $sub_level = $level + 1;
        if (@sub_cate){
            my @sub_category_list = &_get_sub_category_list(\@sub_cate, $blog_id, $sub_level);
            foreach my $sub_category_list (@sub_category_list) {
                push @category_list, $sub_category_list;
            }
        }
    }
    return @category_list;
}

## Exif情報を削除
sub cb_exif_clear {
    my ( $cb, %args ) = @_;

#    MT->log( 'cb_exif_clear 1' );

    my $asset = $args{asset};
    my $blog = $args{blog} || '';

#    MT->log( 'cb_exif_clear 2' );

    my $file_path = $asset->file_path;
    unless ( $file_path ) {
        MT->log({
            class => 'mailpack',
            level => MT::Log::ERROR,
            message => plugin->translate("MailPack: Asset [_1] : no file path.",$asset->id) });
        return 1;
    }

#    MT->log( 'cb_exif_clear 3' );

    use MTCMS::Image;
    MTCMS::Image->error( undef );

    my $orientation = MTCMS::Image->detect_orientation($file_path) or return 1;
    if ($orientation && MTCMS::Image->errstr) {
        MT->log({
            class => 'mailpack',
            level => MT::Log::INFO,
            message => plugin->translate("MailPack: Asset [_1] : Detect orientation : [_2]", $asset->id, MTCMS::Image->errstr) });
        return 1;
    }

#    MT->log( 'cb_exif_clear 3' );

    my $image = MTCMS::Image->new( Filename => $file_path );
    unless ( $image ) {
        MT->log({
            class => 'mailpack',
            level => MT::Log::ERROR,
            message => plugin->translate("MailPack: Asset [_1] : ImageDriver err : [_2]", $asset->id, MTCMS::Image->errstr) });
        return 1;
    }
#    MT->log( 'cb_exif_clear 4' );
    my $blob = $image->rotate_by_orientation($orientation);
    unless ( $blob ) {
        return MT->log({
            class => 'mailpack',
            level => MT::Log::ERROR,
            message => plugin->translate("MailPack: Asset [_1] : Rotation err : [_2]", $asset->id, $image->errstr) });
        return 1;
    }

#    MT->log( 'cb_exif_clear 5' );

    require MT::FileMgr;
    my $file_mgr = $blog ? $blog->file_mgr : MT::FileMgr->new('Local');
    return 1 unless $file_mgr;
    if ( $file_mgr->exists($file_path) ) {
        my $tmp_path = "$file_path.new";
        $file_mgr->put_data($blob, $tmp_path, 'upload');
        $file_mgr->rename($file_path,"$file_path.old");
        $file_mgr->rename($tmp_path,$file_path);
        $file_mgr->delete("$file_path.old");
    }
    else {
        $file_mgr->put_data($blob, $file_path, 'upload');
    }

    require Image::Size;
    my ( $w, $h, $id ) = Image::Size::imgsize( $asset->file_path );
    $asset->image_width( $w );
    $asset->image_height( $h );
    $asset->save;

#    MT->log( 'cb_exif_clear 6' );
    return 1;
}

sub cb_tmpl_param_asset_upload {
    my ($cb, $app, $param) = @_;

    $param->{normalize_orientation} = 1;
}


1;
