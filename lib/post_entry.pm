package post_entry;

use strict;
use warnings;
use Exporter;
@post_entry::ISA = qw(Exporter);
use vars qw(@EXPORT_OK $INSERT_TAG_CONNECTION $INSERT_TAG_START $INSERT_TAG_END);
@EXPORT_OK = qw(post_entry);
use MT;
use MT::Blog;
use MT::Entry;
use MT::Comment;
use MT::Author;
use MT::Placement;
use MT::WeblogPublisher;
use MT::ConfigMgr;
use MT::Image;
use MT::Asset;
use MT::MailPack::MessageId;
use Digest::MD5;
use MTCMS::Image;
#use File::basename;
use File::Copy qw(mv);
use UNIVERSAL::require;
use MailPack::Util qw( get_custom_fields_informations custom_fields_insert_html );
use Data::Dumper;

for my $module (qw/HTML::Parser HTML::Scrubber/){
    $module->use or MT->log(sprintf'[MailPack] could not require %s.', $module);
}

$INSERT_TAG_CONNECTION = '<br/><br/>';
$INSERT_TAG_START = '';
$INSERT_TAG_END = '';

use logmgr;
use logmgr qw(add_logque get_plugin_data);

sub post_entry {
    my ($plugin, $outbound_ref, $logque_ref) = @_;
    my @outbound = @$outbound_ref;
    my @logque = @$logque_ref;
    my @blog_ids;
    my @entry_ids;
    my @entry_arr;

    eval {
        while (@outbound) {
            my $outbound = shift @outbound;
            my $thread_mode = get_plugin_data ($plugin, $outbound->{blogid}, 'comment_thread') || 0;
            my ($entry_id, $comment_id);
            if ($thread_mode && defined $outbound->{'In-Reply-To'}) {
                my $hash = $outbound->{'In-Reply-To'};
                $hash =~ s/\s+$//;
                $hash = Digest::MD5::md5_hex ($hash);
                my $message_id = MT::MailPack::MessageId->load ({ hash => lc $hash }, { limit => 1 });

                # Make a responced message to the entry as a comment
                if ($message_id && $message_id->obj_type == MT::MailPack::MessageId::ENTRY
					&& defined( my $entry = MT::Entry->load({ id => $message_id->obj_id }))) {
                    ($entry_id, $comment_id) = _make_an_comment ($plugin, $outbound, \@logque, $entry);
                    _regist_message_id ($comment_id, MT::MailPack::MessageId::COMMENT, $outbound->{'Message-Id'});
                }
                elsif ($message_id && $message_id->obj_type == MT::MailPack::MessageId::COMMENT
					   && defined( my $parent_comment = MT::Comment->load({ id => $message_id->obj_id }))) {
                    # Make a responced message to the threaded comment
                    if ($thread_mode == 1) {
                        ($entry_id, $comment_id) = _make_an_comment ($plugin, $outbound, \@logque, undef, $parent_comment);
                        _regist_message_id ($comment_id, MT::MailPack::MessageId::COMMENT, $outbound->{'Message-Id'});
                    }
                    # Make a responced message to the root comment
                    elsif (defined( my $entry = MT::Entry->load({ id => $parent_comment->entry_id }))) {
                        ($entry_id, $comment_id) = _make_an_comment ($plugin, $outbound, \@logque, $entry);
                        _regist_message_id ($comment_id, MT::MailPack::MessageId::COMMENT, $outbound->{'Message-Id'});
                    }
                    # Not found, Make a new entry
                    else {
                        ($entry_id, undef) = _make_an_entry ($plugin, $outbound, \@logque);
                        _regist_message_id ($entry_id, MT::MailPack::MessageId::ENTRY, $outbound->{'Message-Id'});
                    }
                }
                # Not found, Make a new entry
                else {
                    ($entry_id, undef) = _make_an_entry ($plugin, $outbound, \@logque);
                    _regist_message_id ($entry_id, MT::MailPack::MessageId::ENTRY, $outbound->{'Message-Id'});
                }
            }
            else {
                # Make a new entry
                ($entry_id, undef) = _make_an_entry ($plugin, $outbound, \@logque);
                _regist_message_id ($entry_id, MT::MailPack::MessageId::ENTRY, $outbound->{'Message-Id'});
            }
            push @entry_arr, {
                entry_id   => $entry_id,
                send_email => $outbound->{send_email},
            };
        }# /while

        # make unique the rebuild queue
        my %eid;
        @entry_arr = grep { !$eid{$_->{entry_id}}++ } @entry_arr;
        # Rebuild the entries
        my $mt = MT->instance;
        foreach my $entry_rec (@entry_arr) {
            my $entry = MT::Entry->load ({ id => $entry_rec->{entry_id}})
                or next;
            my $blog = MT::Blog->load ($entry->blog_id)
                or next;
            if (! $mt->rebuild_entry (Entry => $entry, Blog => $blog, BuildDependencies => 1)) {
                push @logque, add_logque (
					MT::Log->WARNING,
					0,
					$plugin->translate ('MailPack: Failed to rebuild the entry:[_1] (ID: [_2]).',
										$entry->title, $entry->id) . ':' . $mt->errstr,
					$entry->blog_id,
					$entry->author_id);
            }
        }
    };# /eval
    if ($@) {
        my $buf_log = add_logque(MT::Log->ERROR, 0,'[MailPack] post_entry.pm ' . $@);
        push(@logque, $buf_log);
    }
    return (\@entry_arr, \@logque);
}



# Make a new entry
sub _make_an_entry {
    my ($plugin, $outbound, $logque_ref) = @_;
#    my @logque = @$logque_ref;

    my $blog   = MT::Blog->load($outbound->{blogid});
    my $author = MT::Author->load($outbound->{author_id});

    my $send_email = $outbound->{send_email};

    my $title  = $outbound->{content}->{title} || 'No Title';
    my $text   = $outbound->{content}->{description};

    my $scrubber = HTML::Scrubber->new;

    unless(utf8::is_utf8($title)){
        $title = Encode::decode('utf8', $title);
        $title = $scrubber->scrub($title);
    }
    unless(utf8::is_utf8($text)){
        $text = Encode::decode('utf8', $text);
        $text = $scrubber->scrub($text);
    }

    #改行2つはPタグ、１つはbrタグに置換え
    $text = '<p>' . $text . '</p>';
    $text =~ s/\r\n\r\n/<\/p><p>/g;
    $text =~ s/\n\n/<\/p><p>/g;
    $text =~ s/\r\n/<br \/>/g;
    $text =~ s/\n/<br \/>/g;

    # Categories
    my $category_ids = $outbound->{category};
    my ($primary_cat_id, @add_cat ) = split /\s*,\s*/, ( $category_ids || '' );

    #21800 添付ファイルをカスタムフィールドとして登録
    # Custom Fields カスタムフィールドの設定の情報を取得。利用できるカスタムフォールドだけを用意する。用意したカスタムフィールドの並びも重要。
    my $custom_fields = get_custom_fields_informations( $outbound->{blogid} , $outbound->{custom_fields} );
    my @cf_ids;
    @cf_ids = grep { $_->{check} } @$custom_fields if $custom_fields;
    ## カスタムフィールドの必須項目の数。
    my $cf_required_check = 0;
    for ( @cf_ids ) {
        $cf_required_check++ if $_ && $_->{required};
    }

    my $entry = MT::Entry->new;
    $entry->blog_id ($outbound->{blogid});
    $entry->category_id ($primary_cat_id);
    $entry->author_id ($outbound->{author_id});

    my $assist_post_status = &get_plugin_data( $plugin, $entry->blog_id, 'assist_post_status') || 0;
    my $post_status = &get_plugin_data( $plugin, $entry->blog_id, 'post_status') || 0;

    if ( $outbound->{assist} ) {
		$entry->status ( $assist_post_status || $blog->status_default );
    }else{
		$entry->status ( $post_status || $blog->status_default );
    }
    $entry->title ($title);
    $entry->text ($text);
    $entry->allow_comments ($blog->allow_comments_default);
    $entry->allow_pings ($blog->allow_pings_default);

    if ($entry->save) {

		# create logging function
		my $logger = sub {
			my ($level,$msg, $mail) = @_;
			
			my $log_entry = add_logque($level, 0 ,$msg, $entry->blog_id, $entry->author_id, $mail);
			push @$logque_ref, $log_entry;

			return;
		};

        my $author_name = $author->nickname || $author->name;
		$logger->(
			MT::Log->INFO,
			$plugin->translate ('MailPack: Entry:[_2] (ID:[_3]) save. for User:[_1].', $author_name, $entry->title, $entry->id));

        if ($primary_cat_id) {
            my $place = MT::Placement->new;
            $place->is_primary(1);
            $place->entry_id($entry->id);
            $place->blog_id($entry->blog_id);
            $place->category_id($primary_cat_id);
            if (!$place->save) {
                push @$logque_ref, add_logque (
					MT::Log->ERROR,
					0,
					$plugin->translate ('MailPack: Entry:[_1] (ID:[_2]) is category save error. category(ID:[_3])',
										$entry->title, $entry->id, $entry->category_id),
					$entry->blog_id,
					$entry->author_id);
            }

            for my $cat_id (@add_cat) {
                my $place_sub = MT::Placement->new;
                $place_sub->is_primary (0);
                $place_sub->entry_id ($entry->id);
                $place_sub->blog_id ($entry->blog_id);
                $place_sub->category_id ($cat_id);
                if (!$place_sub->save) {
                    push @$logque_ref, add_logque (
						MT::Log->ERROR,
						0,
						$plugin->translate ('MailPack: Entry:[_1] (ID:[_2]) is category save error. category(ID:[_3])',
											$entry->title, $entry->id, $entry->category_id),
						$entry->blog_id,
						$entry->author_id);
                }
            }
        }

        my $asset_text = '';
        my $fileex = $outbound->{fileex};
        my @ts = MT::Util::offset_time_list (time, $blog);
        foreach my $fx (@$fileex) {
            if ($fx) {
                #original  filename
                my $fname_org = $fx->{name};
                $fname_org =~ s!\\!/!g;
                $fname_org =~ s!^.*/!!;

                #extension
                $fname_org =~ m!\.([^.]+)$!;
                my $ext = $1;

                if ( my $deny_exts = MT->config->DeniedAssetFileExtensions ) {
                    my @deny_exts = map { if ( $_ =~ m/^\./ ) { qr/$_/i } else { qr/\.$_/i } } split '\s?,\s?', $deny_exts;
                    my @ret = File::Basename::fileparse( $fname_org, @deny_exts );
                    if ( $ret[2] ) {
		                $logger->( MT::Log->INFO,
			                $plugin->translate ('MailPack: The file([_1]) you uploaded is not allowed.', $fname_org)
                        );
                        next;
                    }
                }

                if ( my $allow_exts = MT->config('AssetFileExtensions') ) {
                    my @allow_exts = map {
                        if   ( $_ =~ m/^\./ ) {qr/$_/i}
                        else                  {qr/\.$_/i}
                    } split '\s?,\s?', $allow_exts;
                    my @ret = File::Basename::fileparse( $fname_org, @allow_exts );
                    unless ( $ret[2] ) {
		                $logger->( MT::Log->INFO,
			                $plugin->translate ('MailPack: The file([_1]) you uploaded is not allowed.', $fname_org)
                        );
                        next;
                    }
                }

                #filename
                my $now = sprintf "%04d%02d%02d%02d%02d%02d", $ts[5]+1900, $ts[4]+1, @ts[3,2,1,0];
                my $fname = $now . '_' . $entry->id . ".$ext";

                #file title
                my $title = $fx->{name};
                $fname_org =~ m!(.+)\.([^.]+)$!;
                $title ||= $1;

                #path
                my $path = "files";
                my $directory = $path;
                my $root_path = $blog->site_path;
                my $root_url = $blog->site_url;

                my $dest_path = File::Spec->catfile($root_path, $path);
                my $dest_file = File::Spec->catfile($dest_path, $fname);
                my $i = 0;
                while (-e $dest_file) {
                    $i++;
                    $fname = $now . '_' . $entry->id . '_' . $i . ".$ext";
                    $dest_file = File::Spec->catfile($dest_path, $fname);
                }

                my $url = $root_url;
                $url .= '/' if $url !~ m!/$!;
                $url .= "$path/" if $path;
                $url .= $fname;

                my $fmgr = $blog->file_mgr;
                unless ($fmgr->exists($dest_path)) {
                    unless ($fmgr->mkpath($dest_path)){
                        push @$logque_ref, add_logque (
							MT::Log->ERROR,
							0,
							$plugin->translate ('MailPack: Entry:[_1] (ID:[_2]) upload dir ([_3]) make error.',
												$entry->title, $entry->id, $dest_path),
							$entry->blog_id,
							$entry->author_id);
                        next;
                    }
                }
                my $cfg = MT::ConfigMgr->instance;
                my $upload_size = $cfg->CGIMaxUpload;
                my $umask = oct $cfg->UploadUmask;
                my $old = umask $umask;

                my $file_size = length($fx->{bits});
                if ($file_size > $upload_size){
                    push @$logque_ref, add_logque (
						MT::Log->ERROR,
						0,
						$plugin->translate ('MailPack: Entry:[_1] (ID:[_2]) upload file ([_3]) file size error.',
											$entry->title, $entry->id, $fname_org),
						$entry->blog_id,
						$entry->author_id);
                    next;
                }

                unless (defined(my $bytes = $fmgr->put_data($fx->{bits}, $dest_file, 'upload'))){
                    push @$logque_ref, add_logque (
						MT::Log->ERROR,
						0,
						$plugin->translate ('MailPack: Entry:[_1] (ID:[_2]) upload file ([_3]) upload error.',
											$entry->title, $entry->id, $fname_org),
						$entry->blog_id,
						$entry->author_id);
                    next;
                }
                umask $old;

				if( $title =~ /%\d/ ){
					$title = MT::Util::decode_url( $title );
				}

        		Encode::_utf8_on( $title ) unless Encode::is_utf8( $title );

                #アイテム登録
                my $add_html = "";
                my $asset = &_save_asset($fname, $dest_file, $url, $title, $entry->blog_id, $entry->author_id, 0);
                if ($asset){

					#fix orientation.
					if ($asset->class eq 'image') {
						_fix_orientation($blog, $plugin, $logger, $asset);
					}

					my $asset_comb = sub { return '<form mt:asset-id="'.$_[0]->id.'" class="mt-enclosure mt-enclosure-'. $_[0]->class .'">'.$_[1].'</form>'; };
                    if( $MT::VERSION >= 5.0 ){

						## $asset , $add_html , $entry, $thumb_asset;
						$asset_comb = sub { 
							require MT::ObjectAsset;
							my ( $asset , $html , $entry , $thumb_asset ) = @_;

							## MT5ではオブジェクトと連結させる。
							my $oa = MT::ObjectAsset->load( { asset_id => $asset->id , blog_id => $entry->blog_id , object_id =>$entry->id , object_ds => $entry->class } );
							unless( $oa ){
								$oa = MT::ObjectAsset->new;
							}
							$oa->asset_id( $asset->id );
							$oa->blog_id( $entry->blog_id );
							$oa->object_id( $entry->id );
							$oa->object_ds( $entry->class );
							$oa->save;
							return $html;
							
						};
                    }

                    my $asset_type = $asset->class;
                    my $asset_id = $asset->id;
                    my $insert_point = &get_plugin_data($plugin, $entry->blog_id, 'insert_point') || 0;
                    push @$logque_ref, add_logque (
						MT::Log->INFO,
						0,
						$plugin->translate ('MailPack: Entry:[_1] (ID:[_2]) upload file ([_3]) save.',
											$entry->title, $entry->id, $fname_org),
						$entry->blog_id,
						$entry->author_id);
                    if ($asset->class eq 'image') {
                        my $thumbnail_width = &get_plugin_data($plugin, $entry->blog_id, 'thumbnail_width') || 200;
						my $thumb_created_flg = 0;
                        if ($asset->image_width > $thumbnail_width){
                            # make a filename of thumbnail image
                            my $thum_filename = $fname;
                            $thum_filename =~ s!(.+)\.([^.]+?)$!$1_thumb.$2!;
                            my $thum_filepath = File::Spec->catfile($dest_path, $thum_filename);
                            my $thum_url = $root_url;
                            $thum_url .= '/' if $thum_url !~ m!/$!;
                            $thum_url .= "$path/" if $path;
                            $thum_url .= $thum_filename;

                            my $thum_title = $plugin->translate('thumbnail of [_1]', $title);
                            my $img = MT::Image->new( Filename => $dest_file );
                            
							# Fix for cases with no image driver
							if($img) { 
								
								my ($blob, $w, $h) = $img->scale( Width => $thumbnail_width);
								open FH, ">$thum_filepath" || die "Can't create $thum_filepath !";
								binmode FH;
								print FH $blob;
								close FH;
								my $thumb_asset = &_save_asset($thum_filename, $thum_filepath, $thum_url, $thum_title, $entry->blog_id, $entry->author_id, $asset->id);
								if ($thumb_asset){
									push @$logque_ref, add_logque (
                                        MT::Log->INFO,
                                        0,
                                        $plugin->translate ('MailPack: Entry:[_1] (ID:[_2]) upload file ([_3]) thumbnail save.',
															$entry->title, $entry->id, $fname_org),
                                        $entry->blog_id,
                                        $entry->author_id);
								}
								$add_html = '<a href="' . $url . '" target="_blank" ><img src="' . $thum_url . '" width="' . $thumb_asset->image_width . '" height="'. $thumb_asset->image_height . '" alt="" /></a>';

								$thumb_created_flg = 1;
							}
						}
						unless ($thumb_created_flg) {
                            $add_html = '<img src="' . $url . '" width="' . $asset->image_width . '" height="' . $asset->image_height . '" alt="" />';
                        }
#                       $add_html = qq{<form mt:asset-id="$asset_id" class="mt-enclosure mt-enclosure-$asset_type">$add_html</form>};
                        # callback for rewriting image embbeded html.
                        MT->run_callbacks('Mailpack::asset_html', $asset, \$add_html);
                        $add_html = &$asset_comb( $asset , $add_html , $entry );  ## MT4 MT5 連結方法 切り替え
                    }else{

						Encode::_utf8_on( $title ) unless Encode::is_utf8( $title );

                        $add_html = '<a href="' . $url . '">' . $title . '</a>';
#                       $add_html = qq{<form mt:asset-id="$asset_id" class="mt-enclosure mt-enclosure-$asset_type">$add_html</form>};
                        $add_html = &$asset_comb( $asset , $add_html , $entry );  ## MT4 MT5 連結方法 切り替え
                    }

					$asset_text .= $add_html;
                    #21800 添付ファイルをカスタムフィールドとして登録
                    ## アイテムをカスタムフィールドに登録する。カスタムフィールドに登録する場合は本文には登録しない。
                    require CustomFields::Util;
                    my $meta = {};
                    for ( my $cf_no = 0; $cf_no < scalar @cf_ids; $cf_no++ ) {
                         if ( $cf_ids[$cf_no]->{type} eq $asset->class ) {

                             $meta->{$cf_ids[$cf_no]->{basename}}
                                 = custom_fields_insert_html( $asset );

                             $cf_required_check-- if $cf_ids[$cf_no]->{required} == 1;

                             splice( @cf_ids , $cf_no , 1 );
                             $asset_text = "";
                             last;
                         }
                    }

                    if ( $asset_text ) {
                        if ($insert_point == 1) {
                            $add_html = $text . $INSERT_TAG_CONNECTION . $INSERT_TAG_START .  $asset_text . $INSERT_TAG_END;
                        } else {
                            $add_html = $INSERT_TAG_START . $asset_text . $INSERT_TAG_END . $INSERT_TAG_CONNECTION . $text;
                        }
                        $entry->text($add_html);
                    } else {
                        $entry->text($text);
                        CustomFields::Util::save_meta( $entry , $meta ) if %$meta;
                    }
                    $entry->save;
                }
                else {
                    push @$logque_ref, add_logque (
						MT::Log->ERROR,
						0,
						$plugin->translate ('MailPack: Entry:[_1] (ID:[_2]) upload file ([_3]) save.',
											$entry->title, $entry->id, $fname_org),
						$entry->blog_id,
						$entry->author_id);
                }
            }
        }

        ## 必須項目のカスタムフィールドに添付ファイルが設定されなかったケース
        if ( $cf_required_check > 0 && $entry->status == MT::Entry::RELEASE() ) {

           push @$logque_ref, add_logque ( 
              MT::Log->ERROR,
              0,
              $plugin->translate ('MailPack: Entry:[_1] - Because not all the required fields filled custom fields, change the status of the draft articles.', $entry->title ),
              $entry->blog_id,
              $entry->author_id,
              $send_email);
           

           $entry->status( MT::Entry::HOLD() ); 
           unless ( $entry->save ) {
           
              push @$logque_ref, add_logque (
                 MT::Log->ERROR,
                 0,
                $plugin->translate ('MailPack: Entry:[_1] save error.', $entry->title),
                $entry->blog_id,
                $entry->author_id,
                $send_email);
           }
        }

    }
    else {
        push @$logque_ref, add_logque (
			MT::Log->ERROR,
			0,
			$plugin->translate ('MailPack: Entry:[_1] save error.', $entry->title),
			$entry->blog_id,
			$entry->author_id,
			$send_email);
    }
    return ($entry->id, $entry->id);
}

sub logger {
	
	undef;
}

# Make an comment
sub _make_an_comment {
    my ($plugin, $outbound, $logque_ref, $entry, $parent_comment) = @_;
#    my @logque = @$logque_ref;

    # Load needed objects
    if (!$entry) {
        $entry = MT::Entry->load ({ id => $parent_comment->entry_id })
            or return undef;
    }
    my $blog = MT::Blog->load ({ id => $outbound->{blogid}})
        or return undef;
    my $author = MT::Author->load ({ id => $outbound->{author_id}})
        or return undef;

    # Generate the comment body
    my $comment_body = <<EOF;
	$outbound->{content}->{title}
	$outbound->{content}->{description}
EOF

    my $scrubber = HTML::Scrubber->new; 

    unless(utf8::is_utf8($comment_body)){
        $comment_body = Encode::decode('utf8', $comment_body);
        $comment_body = $scrubber->scrub($comment_body);
    }

		# Comment posting
		my $comment = new MT::Comment;
    $comment->blog_id ($blog->id);
    $comment->entry_id ($entry->id);
    $comment->author ($author->nickname || $author->name);
    $comment->created_by ($author->id);
    $comment->commenter_id ($author->id);
    if( $outbound->{assist} ){
		$comment->email ( $outbound->{from} );
    }else{
		$comment->email ($author->email);
    }
    $comment->text ($comment_body);
    $comment->created_on (MT::Util::epoch2ts ($blog, $outbound->{content}->{dataCreated} || time));
    $comment->modified_on (MT::Util::epoch2ts ($blog, $outbound->{content}->{dataCreated} || time));
    $comment->parent_id ($parent_comment->id) if $parent_comment;
    $comment->visible (0);
    unless ( $outbound->{assist} ) {
        $comment->visible (1);
    }
    $comment->save;

    push @$logque_ref, add_logque (
		MT::Log->INFO,
		0,
		$plugin->translate ('MailPack: Comment (ID:[_2]) saved by user [_1].',
							$author->name, $comment->id),
		$entry->blog_id,
		$author->id);

    return ($entry->id, $comment->id);
}



#
sub _regist_message_id {
    my ($obj_id, $obj_type, $msg_guid) = @_;
    $msg_guid =~ s/\s+$//;
    $msg_guid = Digest::MD5::md5_hex ($msg_guid);# 32 chars

    my $message_id = MT::MailPack::MessageId->get_by_key({
        obj_id => $obj_id,
        obj_type => $obj_type,
        hash => lc $msg_guid,
														 });
    $message_id->save;
}



#
sub _save_asset{
    my ($basename, $file_path, $url, $title, $blog_id, $author_id, $parent_id) = @_;
    $file_path =~ m!\.([^.]+)$!;
    my $ext = $1;

    my ($fh, $w, $h, $id, $mimetype);
    open $fh, $file_path;
    eval { require Image::Size; };
    if (! $@){
        ( $w, $h, $id ) = Image::Size::imgsize($fh);
    }
    close $fh;

    my $asset_pkg = MT::Asset->handler_for_file($basename);
    my $is_image = 0;
    if (($ext =~ /^jpe?g$/i) || ($ext =~ /^gif$/i) || ($ext =~ /^png$/i)) {
        $is_image = 1;
        $asset_pkg->isa('MT::Asset::Image');
    }




#    my $is_image  = defined($w) && defined($h) && $asset_pkg->isa('MT::Asset::Image');

    my $asset = $asset_pkg->new();
    $asset->label($title);
    $asset->file_path($file_path);
    $asset->file_name($basename);
    $asset->file_ext($ext);
    $asset->blog_id($blog_id);
    $asset->created_by($author_id);
    $asset->modified_by($author_id);
    $asset->url($url);
    $asset->mime_type($mimetype) if $mimetype;
    $asset->description('');
    $asset->parent($parent_id) if $parent_id;

    if ($is_image) {
        $asset->class('image');
        $asset->image_width($w);
        $asset->image_height($h);
    }else{
        $asset->class('file');
    }
    unless ($asset->save){
        return 0;
    }
    return $asset;
}

sub _fix_orientation {
	my  ($blog, $plugin, $logger, $asset) = @_;

    ## for MT6
    if ( $MT::VERSION >= 6 ) {
        if ( $asset->normalize_orientation ) {
            return $logger->(
                MT::Log->INFO,
                $plugin->translate("MailPack: Asset [_1] : Image fix orientation.", $asset->id ));
        }
        else {
            return $logger->(
                MT::Log->ERROR,
                $plugin->translate("MailPack: Asset [_1] : [_2]", $asset->id , $asset->errstr));
        }
    }

	my $file_path = $asset->file_path
		or return $logger->(
			MT::Log->ERROR,
			$plugin->translate("MailPack: Asset [_1] : no file path.", $asset->id));

        ## 初期化 
        MTCMS::Image->error( undef );

	# determine image orientation
	my $orientation = MTCMS::Image->detect_orientation($file_path) or return;

#	MT->log("orientation : $orientation");

	if ($orientation && MTCMS::Image->errstr) {
		return $logger->(
			MT::Log->INFO,
			$plugin->translate("MailPack: Asset [_1] : Detect orientation : [_2]", $asset->id, MTCMS::Image->errstr));
	}

	# Rotate image by its orientation.
	my $image = MTCMS::Image->new(Filename => $file_path)
		or return $logger->(
			MT::Log->ERROR,
			$plugin->translate("MailPack: Asset [_1] : ImageDriver err : [_2]", $asset->id, MTCMS::Image->errstr));

	my $blob = $image->rotate_by_orientation($orientation)
		or return $logger->(
			MT::Log->ERROR,
			$plugin->translate("MailPack: Asset [_1] : Rotation err : [_2]", $asset->id, $image->errstr));

	# replace image with rotated one.
	my $ext_name = $asset->file_ext;
	_safe_file_dump($logger, $blog, \$blob, $file_path, $ext_name)
		or return;

	# Complete orientation fix.
	$logger->(
		MT::Log->INFO,
		$plugin->translate("MailPack: Asset [_1] : Image Rotated by orientation [_2]", $asset->id, $orientation));

	1;
}

# dump the data to file safely.
sub _safe_file_dump {
	my ($logger, $blog, $blob_ref, $path, $ext_name) = @_;
	
	# generate temporary file name.
	my $dir =  File::Basename::dirname($path);
	my $basename = File::Basename::basename($path, $ext_name);
	my $temporal_file_path =  File::Spec->catfile($dir,  $basename . 'tmp');

	my $file_mgr = $blog->file_mgr;

	# if the file is already existed, 
	# then write out blob to temporary file and rename it $path,
	if($file_mgr->exists($path)) {

		$file_mgr->put_data($$blob_ref, $temporal_file_path, 'upload')
			or return $logger->(MT::Log->ERROR, MT->translate("'MailPack: Coundn't write temporal file to :[_1]", $temporal_file_path));

		unlink($path)
			or return $logger->(MT::Log->ERROR, MT->translate("'MailPack: Coundn't remove file :[_1]", $temporal_file_path));

		mv($temporal_file_path, $path)
			or return $logger->(MT::Log->ERROR, MT->translate("'MailPack: Coundn't remove file :[_1] to [_2]", $temporal_file_path, $path));
	} else {
		$file_mgr->put_data($$blob_ref, $path, 'upload')
			or return $logger->(MT::Log->ERROR, MT->translate("'MailPack: Coundn't write file  to :[_1]", $path));

	}

	$path
}

1;
__END__
