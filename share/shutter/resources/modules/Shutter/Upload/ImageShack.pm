###################################################
#
#  Copyright (C) 2008-2011 Mario Kemper <mario.kemper@googlemail.com> and Shutter Team
#
#  This file is part of Shutter.
#
#  Shutter is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 3 of the License, or
#  (at your option) any later version.
#
#  Shutter is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with Shutter; if not, write to the Free Software
#  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
###################################################

=encoding utf8

=head1 NAME

Image::ImageShack - Upload images to be hosted at imageshack.us without needing any account information.

=head1 SYNOPSIS

  require Image::ImageShack;

  my $ishack = Image::ImageShack->new();

  #you can access the LWP::UserAgent via the user_agent method
  #proxy can be specified by
  $ishack->user_agent->proxy(['http'], 'http://localhost:8080/');

  my $image_url = 'http://www.domain.com/image.png';
  
  #upload specifying a url
  my $url1 = $ishack->host($image_url);	#upload with real size, just optimizes
  my $url2 = $ishack->host($image_url, 320);	#resize to 320x240 (for websites and email)

  #upload a file
  my $url3 = $ishack->host('image.jpg');	#upload file

  #get the thumbnail address
  my $thumb_url = $ishack->thumb_url();

  #will croak on error

=head1 DESCRIPTION

Image::ImageShack intends to make programmatically possible to upload image files to the website L<http://imageshack.us/>.

imageshack.us allows you to upload image files (jpg, jpeg, png, gif, bmp, tif, tiff, swf < 1.5 megabytes) and to optimize and or resize these files while making them available to others via imageshack.us servers (even direct linking).

A thumbnail is always created.

=cut

package Shutter::Upload::ImageShack;

use Encode qw(encode);

use utf8;
use LWP::UserAgent;
use HTTP::Response;
use HTTP::Request::Common;
use HTTP::Status;
use HTTP::Cookies;

use Data::Dumper;

#Glib
use Glib qw/TRUE FALSE/; 

#--------------------------------------

use Carp qw(carp croak);

use strict;
use warnings;

our $VERSION = '0.03';
$VERSION = eval $VERSION;

our $url   = 'http://imageshack.us';
our $uri   = 'transload.php';
our $agent = 'Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1)'; #nice "fake"

=head2 Method Summary

=over 4

=item new(attr=>value)

Constructor.
Initializes the object.

Attributes are:

=over 4

=item agent

L<LWP::UserAgent|LWP::UserAgent> object to used make HTTP requests

=item bar

Boolean indicating whether thumbnails should have a black bar at the bottom with real image size

=item login

Id used to upload the files. If you have registered with imageshack.us, you should have received an email with a link similar to: http://reg.imageshack.us/setlogin.php?login=SOME_IDENTIFIER

If you intend to be able to later on use the web interface to erase files, you should pass either that link as the login parameter or only the user_id (SOME_IDENTIFIER).

No verification on the validity of the user_id is currently made

=back

=cut

sub new {
	my ($pack, %attrs) = @_;

	my $self = bless {}, $pack;

	if(ref($attrs{'lwp_ua'}) && $attrs{'lwp_ua'}->isa('LWP::UserAngent')){
		$self->ua($attrs{'lwp_ua'});
	}else{
		my $ua = LWP::UserAgent->new(
			'agent'      => $agent,
			'timeout'    => 30,
			'keep_alive' => 10,
			'env_proxy'  => 1,
		);
		$self->ua($ua);
	}

	$self->ua->cookie_jar(HTTP::Cookies->new(file => "$ENV{HOME}/.cookies.txt"));

	if(defined($attrs{'bar'})){
		$self->{'bar'} = $attrs{'bar'};
	}

	#FOLLOWING ATTS ADDED BY SHUTTER TEAM - quick and dirty - maybe fixme
	$self->{_host} = undef;
	$self->{_username} = undef;
	$self->{_filename} = undef;
	$self->{_url} = undef;
	$self->{_url_thumb} = undef;
	$self->{_status} = undef;
	$self->{_gettext_object} = undef;
	$self->{_main_gtk_window} = undef;
	$self->{_shutter_root} = undef;

	$self->{_notebook} = Gtk2::Notebook->new;
	$self->{_notebook}->set( homogeneous => 1 );
	$self->{_notebook}->set_scrollable(TRUE);
	
	return $self;
}

=over 4

=item user_agent

Returns or sets the L<LWP::UserAgent|LWP::UserAgent> object used internally so that it can the customised

=cut

sub user_agent{
	my ($self, $ua) = @_;
	if(ref($ua) && $ua->isa('LWP::UserAgent')){
		$self->{'_ua'}=$ua;
	}
	return $self->{'_ua'};
}

#just an internal alias
*ua = \*user_agent;

our @optsize = (100, 150, 320, 640, 800, 1024, 1280, 1600, 'resample');

=item host($url, $size)

Given an url (starts with http:// or https://) or a filename and a width in pixels uploads the image to image imageshack.us and resizes it to the desired size.
Returns the url of the hosted image and croaks on error.

Possible values for C<$size> are:

=over 4

=item B<100>

100 x 75 (avatar) 

=item B<150>

150x112 (thumbnail)

=item B<320>

320 x 240 ( for websites and email ) 

=item B<640>

640x480 (for message boards)

=item B<800>

800 x 600 ( 15 -inch monitor ) 

=item B<1024>

1024x768 (17-inch monitor)

=item B<1280>

1280 x 1024 ( 19 -inch monitor ) 

=item B<1600>

1600x1200 (21-inch monitor)

=item B<resample>

just optimizes

=back

=cut

sub host{
	my ($self, $image, $size) = @_;

	my $upload_filename = encode('UTF-8', $image);

	if(!defined($url)){
		croak("No url to host");
	}

	my %params = (
		'uploadtype' => 'on',
		'brand'      => '',
		'refer'      => ''
	);

	my $is_external = $upload_filename =~ m{^https??://};
	if($is_external){
		$params{'url'} = $upload_filename;
	}else{
		$params{'fileupload'} = [$upload_filename];
		$params{'MAX_FILE_SIZE'} = 3145728;
		#XXX is this really necessary
		$params{'url'} = '';
	}

	if(defined($size)){
	
		$params{'optimage'} = 1;

		if($size=~/^\d+$/){
			if(grep{$_ eq $size}@optsize){
				$size="${size}x${size}";
			}else{
				croak("unknown size $size");
			}
		}

		$params{'optsize'} = $size;

		if($self->{'bar'}){
			delete($params{'rembar'});
		}else{
			$params{'rembar'}=1;
		}
	}

	my @params = (
		"$url/" . ($is_external ? $uri : ''),
		'Content_Type' => 'form-data',
		'Content' => [%params]
	);
	
	my $req = HTTP::Request::Common::POST(@params);
	push @{ $self->ua->requests_redirectable }, 'POST';
	my $rsp = $self->ua->request($req);

	if($rsp->is_success){
		my $txt = $rsp->content;
		print $txt, "\n";
		
		#with account
		if($self->{_username} ne '' && $self->{_password} ne ''){
			if($txt =~ /link-directlink-click.+>(.*)<\/textarea>.*link-widget-click/ism){
				$self->hosted($1);
				
				#short link
				if($txt =~ /link-shortlink-click.+?value=['"]*([^'"]+)['"]*/ism){
					$self->hosted_short($1);
				}else{
					#no short link available
					$self->hosted_short(undef);
				}

				#forum thumb link
				if($txt =~ /thumb-forum-click.+>(.*)<\/textarea>.*thumb-alt-click/ism){
					$self->hosted_thumb($1);
				}else{
					#no short link available
					$self->hosted_thumb(undef);
				}

				return $self->hosted;
			}else{
				croak("direct link not found in. Maybe an error ocurred during upload. [".$rsp->as_string."]");
			}
		#anony. login -> no user, no password
		}else{
			if($txt =~ /Direct Link.+value=['"]*([^'"]+)['"].*to get this link/ism){
				$self->hosted($1);
				
				#short link
				if($txt =~ /link-shortlink-click.+?value=['"]*([^'"]+)['"]*/ism){
					$self->hosted_short($1);
				}else{
					#no short link available
					$self->hosted_short(undef);
				}

				#forum thumb link
				if($txt =~ /thumb-forum-click.+>(.*)<\/textarea>.*thumb-alt-click/ism){
					$self->hosted_thumb($1);
				}else{
					#no short link available
					$self->hosted_thumb(undef);
				}

				return $self->hosted;
			}else{
				croak("direct link not found in. Maybe an error ocurred during upload. [".$rsp->as_string."]");
			}			
		}
	}else{
		#XXX debug
		croak($rsp->status_line."[".$rsp->as_string."]")
	}
}

my $gen_method = sub{
	my $field = shift;

	return sub{
		my ($self, $val) = @_;
		if(defined($val)){
			$self->{$field}=$val;
		}

		return $self->{$field};
	};
};

*bar    = $gen_method->('bar');

=item hosted

Returns the url of the last uploaded image.

=cut

*hosted = $gen_method->('hosted');

=item hosted_thumb

Returns the url of the forum thumbnail last uploaded image.
Could be non existent for small images.

=cut

*hosted_thumb = $gen_method->('hosted_thumb');

=item hosted_short

Returns the url of the short link of last uploaded image.
Could be non existent.

=cut

*hosted_short = $gen_method->('hosted_short');

=item login

Returns or sets the user_id.

=cut

sub login{
	my $self 		= shift;
	my $username 	= shift;
	my $password 	= shift;

	$self->{_username} = $username;
	$self->{_password} = $password;

	#Login authentication
	#anonym. authentication with empty password
	if($self->{_username} ne '' && $self->{_password} ne ''){
		my %authparams = (
			'username' => $self->{_username},
			'password' => $self->{_password},
		);
		my @authparams = (
			"$url/auth.php",
			'Content_Type' => 'form-data',
			'Content' => [%authparams]
		);
		my $authreq = HTTP::Request::Common::POST(@authparams);
		push @{ $self->ua->requests_redirectable }, 'POST';
		my $authrsp = $self->ua->request($authreq);
		unless($authrsp->is_success && $authrsp->content eq 'OK'){		
			#XXX debug
			croak($authrsp->status_line."[".$authrsp->as_string."]");
		}
	}
	return $self;
}


=item logout

Resets user_id. From now on images won't be associated with any user.

=cut

sub logout{
	my $self = shift @_;

	$self->ua->cookie_jar->clear;

	return $self;
}

# Preloaded methods go here.
sub create_tab {
	my $self = shift;

	#Clipboard
	my $clipboard = Gtk2::Clipboard->get( Gtk2::Gdk->SELECTION_CLIPBOARD );

	#Tooltips
	my $tooltips = Gtk2::Tooltips->new;

	my $upload_hbox  = Gtk2::HBox->new( FALSE, 0 );
	my $upload_hbox1 = Gtk2::HBox->new( TRUE,  10 );
	my $upload_hbox2 = Gtk2::HBox->new( FALSE, 10 );
	my $upload_hbox3 = Gtk2::HBox->new( TRUE,  10 );
	my $upload_hbox4 = Gtk2::HBox->new( FALSE, 10 );
	my $upload_hbox5 = Gtk2::HBox->new( TRUE,  10 );
	my $upload_hbox6 = Gtk2::HBox->new( FALSE, 10 );
	my $upload_hbox7 = Gtk2::HBox->new( TRUE,  10 );
	my $upload_hbox8 = Gtk2::HBox->new( FALSE, 10 );
	my $upload_vbox  = Gtk2::VBox->new( FALSE, 0 );
	my $label_status = Gtk2::Label->new( $self->{_gettext_object}->get("Upload status:") . " " . status_message($self->{_status}) );

	$upload_hbox->pack_start( Gtk2::Image->new_from_pixbuf( Gtk2::Gdk::Pixbuf->new_from_file_at_scale( "$self->{_shutter_root}/share/shutter/resources/icons/logo-imageshack.png", 100, 100, TRUE ) ), TRUE, TRUE, 0 );
	$upload_hbox->pack_start( $label_status, TRUE, TRUE, 0 );

	my $entry_direct = Gtk2::Entry->new();
	my $entry_hotweb = Gtk2::Entry->new();
	
	#optional thumb and short
	my $label_thumb1 = Gtk2::Label->new( $self->{_gettext_object}->get("Thumbnail for forums") );
	my $label_short1 = Gtk2::Label->new( $self->{_gettext_object}->get("Short URL") );
	
	my $label_direct = Gtk2::Label->new( $self->{_gettext_object}->get("Direct link") );
	my $label_hotweb = Gtk2::Label->new( $self->{_gettext_object}->get("Hotlink for websites") );

	$entry_direct->set_text("$self->{_url}");
	$entry_hotweb->set_text("<a href=\"http:\/\/imageshack.us\"><img src=\"$self->{_url}\" border=\"0\" title=\"Image Hosted by ImageShack.us\" alt=\"Image Hosted by ImageShack.us\"\/><\/a><br\/>Uploaded with <a href=\"http:\/\/shutter-project.org\">Shutter<\/a>");
	$upload_vbox->pack_start( $upload_hbox, TRUE, TRUE, 10 );
	
	#thumbnail
	if ($self->{_url_thumb}) {
		my $entry_thumb1 = Gtk2::Entry->new();

		my $upload_copy1 = Gtk2::Button->new;
		$tooltips->set_tip( $upload_copy1, $self->{_gettext_object}->get("Copy this code to clipboard") );
		$upload_copy1->set_image( Gtk2::Image->new_from_stock( 'gtk-copy', 'menu' ) );
		$upload_copy1->signal_connect(
			'clicked' => sub {
				my ( $widget, $entry ) = @_;
				$clipboard->set_text( $entry->get_text );
			},
			$entry_thumb1
		);

		$entry_thumb1->set_text($self->{_url_thumb});
		$upload_hbox1->pack_start_defaults($label_thumb1);
		$upload_hbox1->pack_start_defaults($entry_thumb1);
		$upload_hbox2->pack_start_defaults($upload_hbox1);
		$upload_hbox2->pack_start( $upload_copy1, FALSE, TRUE, 10 );

	}
	
	#short link
	if ($self->{_url_short}) {
		my $entry_short1 = Gtk2::Entry->new();

		my $upload_copy2 = Gtk2::Button->new;
		$tooltips->set_tip( $upload_copy2, $self->{_gettext_object}->get("Copy this code to clipboard") );
		$upload_copy2->set_image( Gtk2::Image->new_from_stock( 'gtk-copy', 'menu' ) );
		$upload_copy2->signal_connect(
			'clicked' => sub {
				my ( $widget, $entry ) = @_;
				$clipboard->set_text( $entry->get_text );
			},
			$entry_short1
		);

		$entry_short1->set_text($self->{_url_short});
		$upload_hbox3->pack_start_defaults($label_short1);
		$upload_hbox3->pack_start_defaults($entry_short1);
		$upload_hbox4->pack_start_defaults($upload_hbox3);
		$upload_hbox4->pack_start( $upload_copy2, FALSE, TRUE, 10 );
		
	}
	
	my $upload_copy3 = Gtk2::Button->new;
	$tooltips->set_tip( $upload_copy3, $self->{_gettext_object}->get("Copy this code to clipboard") );
	$upload_copy3->set_image( Gtk2::Image->new_from_stock( 'gtk-copy', 'menu' ) );
	$upload_copy3->signal_connect(
		'clicked' => sub {
			my ( $widget, $entry ) = @_;
			$clipboard->set_text( $entry->get_text );
		},
		$entry_direct
	);

	my $upload_copy4 = Gtk2::Button->new;
	$tooltips->set_tip( $upload_copy4, $self->{_gettext_object}->get("Copy this code to clipboard") );
	$upload_copy4->set_image( Gtk2::Image->new_from_stock( 'gtk-copy', 'menu' ) );
	$upload_copy4->signal_connect(
		'clicked' => sub {
			my ( $widget, $entry ) = @_;
			$clipboard->set_text( $entry->get_text );
		},
		$entry_hotweb
	);

	$upload_hbox5->pack_start_defaults($label_direct);
	$upload_hbox5->pack_start_defaults($entry_direct);
	$upload_hbox6->pack_start_defaults($upload_hbox5);
	$upload_hbox6->pack_start( $upload_copy3, FALSE, TRUE, 10 );
	$upload_hbox7->pack_start_defaults($label_hotweb);
	$upload_hbox7->pack_start_defaults($entry_hotweb);
	$upload_hbox8->pack_start_defaults($upload_hbox7);
	$upload_hbox8->pack_start( $upload_copy4, FALSE, TRUE, 10 );

	$upload_vbox->pack_start_defaults($upload_hbox2);
	$upload_vbox->pack_start_defaults($upload_hbox4);
	$upload_vbox->pack_start_defaults($upload_hbox6);
	$upload_vbox->pack_start_defaults($upload_hbox8);
	
	return $upload_vbox;
}

sub show_all {
	my $self = shift;

	#are there any uploaded files?
	return FALSE if $self->{_notebook}->get_n_pages < 1;

	my $dlg_header = $self->{_gettext_object}->get("Upload") . " - " . $self->{_host} . " - " . $self->{_username};
	my $upload_dialog = Gtk2::Dialog->new( $dlg_header, $self->{_main_gtk_window}, [qw/modal destroy-with-parent/], 'gtk-ok' => 'accept' );
	$upload_dialog->set_default_response('accept');

	$upload_dialog->vbox->add($self->{_notebook});
	$upload_dialog->show_all;
	my $upload_response = $upload_dialog->run;

	if ( $upload_response eq "accept" ) {
		$upload_dialog->destroy();
		return TRUE;
	} else {
		$upload_dialog->destroy();
		return FALSE;
	}
}

sub show {
	my ( $self, $host, $username, $filename, $url, $url_thumb, $url_short, $status, $d, $window, $shutter_root ) = @_;

	$self->{_host} = $host;
	$self->{_username} = $username;
	$self->{_filename} = $filename;
	$self->{_url} = $url;
	$self->{_url_thumb} = $url_thumb;
	$self->{_url_short} = $url_short;
	$self->{_status} = $status;
	$self->{_gettext_object} = $d;
	$self->{_main_gtk_window} = $window;
	$self->{_shutter_root} = $shutter_root;

	$self->{_notebook}->append_page( $self->create_tab(), $self->{_filename} );
	
	return TRUE;
}


1;
__END__

=back

=back

=head1 DISCLAIMER

The author declines ANY responsibility for possible infringement of ImageShack® Terms of Service.

This module doesn't use imageshack's XML API but the HTML/web interface instead.

=head1 TO-DO

=over 4

No guarantee that this will ever be implemented

=item HTML code for forums, thumbnails, websites, etc (if you really need this, please ask the author)

=item File deletin

=item Implement XML API (probably never or on a different)

=back


=head1 SEE ALSO

L<LWP::UserAgent|LWP::UserAgent>

http://imageshack.us

http://reg.imageshack.us/content.php?page=faq

http://reg.imageshack.us/content.php?page=rules

=head1 AUTHOR

Cláudio Valente, E<lt>plank@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008 by Cláudio Valente

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut
