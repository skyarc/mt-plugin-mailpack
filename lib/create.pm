package create;

use strict;
use warnings;
use Exporter;
@create::ISA = qw(Exporter);
use vars qw(@EXPORT_OK);
@EXPORT_OK = qw(createblogque);
use logmgr;
use logmgr qw(add_logque);

use MT;
use MT::Object;
use MT::App;
use MT::Blog;
use MT::Category;
use MT::Log;
use MT::ConfigMgr;
use MT::I18N;
use MIME::Base64;
use File::Basename;
use Encode;

sub createblogque {
    my ($plugin, $inbound_ref,$logque_ref) = @_;
    my @inbound = @$inbound_ref;

    my @logque = @$logque_ref;
    my @outbound;

    eval {
        my @post_settings;
        my @obj = MT::Mailpackaddress->load({},{sort => 'email'});

        my %tmp;
        my @ref_array = grep(!$tmp{$_->email}++,@obj);

        foreach my $data_rec (@ref_array) {
            my $category_ids = '';
            my @mailpackaddress = MT::Mailpackaddress->load({email => $data_rec->email});

            foreach my $dat (@mailpackaddress) {
                if ($dat->category_id){
                    if ($category_ids ne ''){
                        $category_ids .= ',' . $dat->category_id;
                    }else{
                        $category_ids .= $dat->category_id;
                    }
                }
            }
            my $buf_post_setting = {
                Post_Adress => $data_rec->email,
                Blog_ID     => $data_rec->blog_id,
                Category_ID => $category_ids,
                Filter_type => $data_rec->filter_type || 0,
                Assist_id  => $data_rec->filter_type ? $data_rec->assist_id || 0 : 0,
                #21800 添付ファイルをカスタムフィールドとして登録
                CustomFields => $data_rec->cf_ids || '',
            };
            push(@post_settings, $buf_post_setting);
        }

        while(@inbound){
            my $entity = shift(@inbound);
            my $head = $entity->head;

            ## 文字コード設定
            set_header_encode( $entity );
            set_encode_info( $entity , 9 , 0 );

            $head->decode;
            my @post_adress;

            my $buf_mail_to = $head->get('To');
            my @buf_mail_to_arr = split(/\,/, $buf_mail_to);
            while(@buf_mail_to_arr){
                my $adress = shift(@buf_mail_to_arr);
                if ($adress =~ m/([\w\-.]+@[\w\-]+(\.[\w\-]+)+)/g){
                    if ($& eq $entity->{mail_box}){
                        push(@post_adress, $&);
                    }
                }
            }
            my $buf_mail_cc = $head->get('cc');
            if ($buf_mail_cc){
                my @buf_mail_cc_arr = split(/\,/, $buf_mail_cc);
                while(@buf_mail_cc_arr){
                    my $adress = shift(@buf_mail_cc_arr);
                    if ($adress =~ m/([\w\-.]+@[\w\-]+(\.[\w\-]+)+)/g){
                        if ($& eq $entity->{mail_box}){
                            push(@post_adress, $&);
                        }
                    }
                }
            }
            my %tmp = ();
            @post_adress = grep(!$tmp{$_}++, @post_adress);

            if (@post_adress) {
                foreach my $setting_adress (@post_settings) {
                    foreach my $to_adress (@post_adress) {
                        if ($to_adress eq $setting_adress->{Post_Adress}) {
                            my $buf_outbound = generate_outbound($plugin, $entity, $setting_adress->{Blog_ID}, $setting_adress->{Category_ID}, $setting_adress->{Post_Adress}, $setting_adress->{Filter_type} , $setting_adress->{Assist_id} , $setting_adress->{CustomFields}, \@logque );
                            if ($buf_outbound){
                                push(@outbound, $buf_outbound);
                            }
                        }
                    }
                }
            }else{
                push(@logque, add_logque(MT::Log->ERROR, 0, $plugin->translate('MailPack: The email address ([_1]) is not found. from to,cc', $entity->{mail_box})));
            }
        }
    };
    if ($@) {
        push(@logque, add_logque(MT::Log->ERROR, 0, "[MailPack] create.pm " . $@));
    }
    return (\@outbound,\@logque);
}

sub generate_outbound {
    my ($plugin, $entity, $post_blog, $post_category, $send_email , $filter_type , $assist_id , $cf_ids , $logque_ref ) = @_;
    my $buf_outbound = "";
    my $content;
    my @fileex = ();
    my $assist = 0; ## 送信者がMovableTypeに登録されていない場合(1)
    eval {
        my $head = $entity->head;
        $head->decode;

        my $email = $head->get('From');
        my $fromaddress;
        if ($email =~ m/([\w\-.]+@[\w\-]+(\.[\w\-]+)+)/g){
            $fromaddress = $&;
        }

        require MT::Author;
        my $author = '';
        if( $filter_type == 2 ){
            if ( $assist_id )
            {
                $author = MT::Author->load({ id => $assist_id , status => MT::Author->ACTIVE } );
                $assist = 1;
            }
        }
        else
        {
            $author = MT::Author->load({ email=>$fromaddress, status => MT::Author->ACTIVE } );
            unless ( $author )
            {
                if ( $filter_type == 1 && $assist_id )
                {
                     $author = MT::Author->load({ id => $assist_id , status => MT::Author->ACTIVE } );
                     $assist = 1;
                }
            }
        }

        if ( $author ){
            my $author_id = $author->id;
            my $username = $author->nickname || $author->name;
            my $password = $author->api_password;

            #投稿権限チェック
            if (! $author->is_superuser) {
                my $perms = MT::Permission->load({ blog_id => $post_blog, author_id => $author->id });
                if (! $perms){
                    push(@$logque_ref, add_logque(MT::Log->ERROR, 0, $plugin->translate('MailPack: USER:[_1](ID:[_2]) no contribution authority.', $username, $author_id), $post_blog, $author_id, $send_email));
                    return $buf_outbound;
                }
                if (! $perms->can_post){
                    push(@$logque_ref, add_logque(MT::Log->ERROR, 0, $plugin->translate('MailPack: USER:[_1](ID:[_2]) no contribution authority.', $username, $author_id), $post_blog, $author_id, $send_email));
                    return $buf_outbound;
                }
            }

            my $cfg = MT::ConfigMgr->instance;
            my $charset = select_enc($cfg->PublishCharset , "utf8");

            my $subject = $head->get('Subject') || '';
            if ( $subject && get_charset($head->get('Subjectencode')) ) {
               $subject = MT::I18N::encode_text( $subject , get_charset($head->get('Subjectencode')) || 'jis' , $charset );
               $subject =~ s/[\x00-\x1f]//g;
            }

            my $date = $head->get ('Date');
            use HTTP::Date;
            chomp $date;
            $date = HTTP::Date::str2time ($date);

            my ($body, $mt_convert_breaks, $fileex) = get_mail_data($entity, 9, 0);
            @fileex = @$fileex;

            my $in_reply_to = scalar $head->get ('In-Reply-To');
            chomp $in_reply_to if defined $in_reply_to;
            my $message_id = scalar $head->get ('Message-Id');
            chomp $message_id if defined $message_id;
            $buf_outbound = {
                blogid     => $post_blog,
                postid     => 0,
                category   => $post_category,
                author_id  => $author_id,
                username   => $author->name,
                password   => $password,
                assist     => $assist,
                from       => $fromaddress,
                send_email => $send_email,
                content => {
                    title       => $subject,
                    description => $body,
                    dataCreated => $date,
                    mt_convert_breaks => $mt_convert_breaks,
                },
                fileex        => \@fileex,
                'In-Reply-To' => $in_reply_to,
                'Message-Id'  => $message_id,
                #21800 添付ファイルをカスタムフィールドとして登録
                #カスタムフィールドのIDがコンマ区切りで保存
                'custom_fields' => $cf_ids,
            };
        }else{
            push(@$logque_ref, add_logque(MT::Log->ERROR, 0, $plugin->translate('MailPack: FromMail:[_1] not find user.', $fromaddress), $post_blog));
        }
    };
    if ($@) {
        push(@$logque_ref, add_logque(MT::Log->ERROR, 0, "[MailPack] create.pm " . $@, $post_blog));
    }
    return $buf_outbound;
}

sub get_mail_data{
    my($entity, $breaks, $iLvl) = @_;
    $iLvl = 0 unless $iLvl;

    my $mail_body = '';
    my $orig      = '';
    my $enc       = '';
    my @fileex = ();
    my ($fileex_rec,$filename,$title,$f_entity);

    my $cfg = MT::ConfigMgr->instance;
    my $charset = select_enc($cfg->PublishCharset , "utf8");
    unless ($entity->is_multipart){

        #シンルグパートの場合
        $orig = $entity->bodyhandle->as_string;
        if( $entity->head->get("Content-Type") ){
             $enc = select_enc( get_content_charset($entity->head->get("Content-Type") ) , "" );
             $orig = MT::I18N::encode_text( $orig, $enc , $charset ) if $enc;
        }
        $mail_body .= $orig;

    }else{

        my $parts_cnt = $entity->parts;
        for (my $i=0; $i<$parts_cnt; $i++) {

            #マルチパートの場合
            if($entity->parts($i)->is_multipart) {
                my ($buf, $bk) = get_mail_data($entity->parts($i), $breaks, $iLvl+1);
                $breaks = $bk;
                $mail_body .= $buf;

            }else{
                if($entity->parts($i)->mime_type eq "text/plain") {

                    #ファイル名が設定されている物はテキストファイルとして処理
                    unless ($entity->parts($i)->head->recommended_filename){

                        #テキスト処理
                        $breaks = 1;
                        $orig = $entity->parts($i)->bodyhandle->as_string;
                        if( $entity->parts($i)->head->get("Content-Type") ){
                             $enc = select_enc(get_content_charset($entity->parts($i)->head->get("Content-Type") ) , "" );
                             $orig = MT::I18N::encode_text( $orig, $enc , $charset ) if $enc;
                        }
                        $mail_body .= $orig;

                    }else{

                            #添付ファイル処理
                            $filename = $entity->parts($i)->bodyhandle->path;
                            $enc = get_charset($entity->parts($i)->head->get("Filenameencode")) || 'jis';
                            $filename = MT::I18N::encode_text($filename, $enc, $charset);
                            #$filename = jcode($filename)->mime_decode->utf8;
                            $filename = (fileparse($filename))[0];
                            $title    = $filename;
                            $f_entity = encode_base64($entity->parts($i)->bodyhandle->as_string,'');
                            # Base64デコード
                            $f_entity = decode_base64($f_entity);
                            # 構造体fileex生成----------------------------
                            $fileex_rec = {
                                name  => $filename,
                                title => $title,
                                bits  => $f_entity,
                            };
                            #---------------------------------------------
                            push(@fileex, $fileex_rec);
                    }
                }elsif($entity->parts($i)->mime_type eq "text/html") {

                    next;
                    #HTML処理
                    #$breaks = 0;
                    #$mail_body .= $entity->parts($i)->bodyhandle->as_string;

                }else{

                    unless (($entity->parts($i)->mime_type =~ m!(application/ms-tnef)!i) or 
                            ($entity->parts($i)->mime_type =~ m!(application/pgp-.*)!i)) {

                        #添付ファイル処理
                        $filename = $entity->parts($i)->bodyhandle->path;
                        $enc = get_charset($entity->parts($i)->head->get("Filenameencode")) || 'jis';
                        $filename = MT::I18N::encode_text($filename, $enc , $charset);
                        #$filename = jcode($filename)->mime_decode->utf8;
                        $filename = (fileparse($filename))[0];
                        $title    = $filename;
                        $f_entity = encode_base64($entity->parts($i)->bodyhandle->as_string,'');
                        # Base64デコード
                        $f_entity = decode_base64($f_entity);
                        # 構造体fileex生成----------------------------
                        $fileex_rec = {
                            name => $filename,
                            title => $title,
                            bits => $f_entity,
                        };
                        #---------------------------------------------
                        push(@fileex, $fileex_rec);
                    }
                }
            }
        }
    }
    return ($mail_body, $breaks, \@fileex);
}


##
## メールヘッダの文字コード設定
##
sub set_header_encode {
   my $entity = shift;
   my $head = $entity->head;
   for( 'From' , 'Subject' ){
       $head->set( $_."encode" ,  select_enc( get_item_charset( $head->get($_) ) , "ISO-2022-JP" ) ) if $head->get($_);
   }
}

##
## マルチパート条件化での各パートの文字コード設定
##
sub set_encode_info { 
    my ( $entity , $iLvl ) = @_;
    my $head = '';

    #シンルグパート
    unless ($entity->is_multipart){
       my $head = $entity->head;
       return;
    }

    #マルチパート
    my $parts_cnt = $entity->parts;
    for (my $i=0; $i<$parts_cnt; $i++) {

       #マルチパード 再帰処理
       if($entity->parts($i)->is_multipart) {
            set_encode_info( $entity->parts($i), $iLvl+1 );
            next;
       }

       my $mime_type = $entity->parts($i)->mime_type;
       $head = $entity->parts($i)->head;

       ## HTMLは処理しない
       next if $mime_type eq "text/html";

       ## テキスト
       if( $mime_type eq "text/plain" ){
           if( $head->recommended_filename ){
               $head->set( 'Nameencode' ,  select_enc( get_name_charset( $head->get("Content-Type") ) , '' ) ) if $head->get("Content-Type");
               $head->set( 'Filenameencode' ,  select_enc( get_file_charset( $head->get("Content-Disposition") ) , '' ) ) if $head->get("Content-Disposition");
           }
           next;
       }
       unless (($entity->parts($i)->mime_type =~ m!(application/ms-tnef)!i) or 
               ($entity->parts($i)->mime_type =~ m!(application/pgp-.*)!i)) {
               $head->set( 'Nameencode' ,  select_enc( get_name_charset( $head->get("Content-Type") ) , '' ) ) if $head->get("Content-Type");
               $head->set( 'Filenameencode' ,  select_enc( get_file_charset( $head->get("Content-Disposition") ) , '' ) ) if $head->get("Content-Disposition");
       }
    }
}

##
## エンコードされたヘッダフィールドの文字コードを抽出
##
sub get_item_charset {
   return $_[0] && $_[0] =~ m/=\?([^\?]+)\?B\?/g ? $1 : '';
}
sub get_content_charset {
   return $_[0] && $_[0] =~ m/charset=\"?([a-zA-Z0-8\-\_]+)\"?/ig ? $1 : '';
}
sub get_name_charset {
   return $_[0] && $_[0] =~ m/name[^=]*=\"?=\?([^\?]+)\?B\?/ig ? $1 : '';
}
sub get_file_charset {
   return '' unless $_[0];
   if( $_[0] =~ m/filename[^=]*=([A-Za-z0-9_-]+)\'/ig ){
      return $1;
   }elsif( $_[0] =~ m/filename[^=]*=\"?=\?([^\?]+)\?B\?/ig ){ 
      return $1;
   }
   return '';
}
sub get_charset {
   return $_[0] && $_[0] =~ m/(sjis|jis|euc|utf8)/i ? $1 : '';
}
##
## 対応する文字コード名を選択
##
sub select_enc {
  return {
        'shift_jis'   => 'sjis',
        'iso-2022-jp' => 'jis',
        'euc-jp'      => 'euc',
        'utf-8'       => 'utf8',
   }->{lc $_[0]} || $_[1];
}

1;
__END__
