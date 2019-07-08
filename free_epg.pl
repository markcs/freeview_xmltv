#!/usr/bin/perl
use strict;
use warnings;
use JSON;
use DateTime;
use Getopt::Long;
use LWP::UserAgent;
use XML::Writer;

my %map = (
    '&' => 'and',
);
my $chars = join '', keys %map;

my @CHANNELDATA;
my @GUIDEDATA;
my @regions = (
    "region_national",
    "region_nsw_sydney",
    "region_nsw_newcastle",
    "region_nsw_taree",
    "region_nsw_tamworth",
    "region_nsw_orange_dubbo_wagga",
    "region_nsw_northern_rivers",
    "region_nsw_wollongong",
    "region_nsw_canberra",
    "region_nt_regional",
    "region_vic_albury",
    "region_vic_shepparton",
    "region_vic_bendigo",
    "region_vic_melbourne",
    "region_vic_ballarat",
    "region_vic_gippsland",
    "region_qld_brisbane",
    "region_qld_goldcoast",
    "region_qld_toowoomba",
    "region_qld_maryborough",
    "region_qld_widebay",
    "region_qld_rockhampton",
    "region_qld_mackay",
    "region_qld_townsville",
    "region_qld_cairns",
    "region_sa_adelaide",
    "region_sa_regional",
    "region_wa_perth",
    "region_wa_regional_wa",
    "region_tas_hobart",
    "region_tas_launceston",
    );

my ($VERBOSE, $pretty, $NUMDAYS, $REGION, $outputfile, $help) = (0, 0, 7, undef, undef, undef);
GetOptions
(
	'verbose'	=> \$VERBOSE,
	'pretty'	=> \$pretty,
  'days=i'    => \$NUMDAYS,
  'region=s'    => \$REGION,
	'output=s'	=> \$outputfile,
	'help|?'	=> \$help,
) or die ("Syntax Error!  Try $0 --help");
die usage() if ($help);    

if (!defined($REGION)) {
        print "\nPlease use the command.\n\tfree_epg.pl --region=<region> --output=<output xmltv filename>.\n\n\tREGION-NAME is one of the following:\n";
        print "\t\t$_\n" foreach(@regions);
        print "\n";
        exit();      
}

elsif (defined($REGION)) {
    if (!( grep( /^$REGION$/, @regions ) ) ) {
        print "\nInvalid region specified.  Please use one of the following:\n";
        print "\t\t$_\n" foreach(@regions);
        exit();
    }
}
warn("Options...\nVerbose = $VERBOSE, days = $NUMDAYS, pretty = $pretty, region=$REGION, output=$outputfile\n\n") if ($VERBOSE);

getchannels();
getepg();
my $XML = XML::Writer->new( OUTPUT => 'self', DATA_MODE => ($pretty ? 1 : 0), DATA_INDENT => ($pretty ? 8 : 0) );
$XML->xmlDecl("ISO-8859-1");
$XML->doctype("tv", undef, "xmltv.dtd");
$XML->startTag('tv', 'generator-info-url' => "http://www.xmltv.org/");

printchannels(\$XML);
printepg(\$XML);
$XML->endTag('tv');

if (!defined $outputfile)
{
	warn("Finished! xmltv guide follows...\n\n") if ($VERBOSE);
	print $XML;
} else {
	warn("Writing xmltv guide to $outputfile...\n") if ($VERBOSE);
	open FILE, ">$outputfile" or die("Unable to open $outputfile file for writing: $!\n");
	print FILE $XML;
	close FILE;
	warn("Done!\n") if ($VERBOSE);
}
exit 0;

exit();


sub getchannels {
   my $data;
   my $ua = LWP::UserAgent->new;
   $ua->agent("FreeView-EPG-Fetch/1.0");
   warn("Getting channel list from FreeView ...\n") if ($VERBOSE);
   my $url = "https://fvau-api-prod.switch.tv/content/v1/channels/REGION/".$REGION."?limit=100&offset=0&include_related=1&expand_related=full&related_entity_types=images";
   my $res = $ua->get($url);
   if ($res->is_success) {
       $data = $res->content;
   } else {
      die "Unable to connect to FreeView.\n";
   }
   my $tmpchanneldata = decode_json($data);   
   $tmpchanneldata = $tmpchanneldata->{data};
   for(my $count=0;$count<@$tmpchanneldata;$count++){
         $CHANNELDATA[$count]->{dvb_triplet} = $tmpchanneldata->[$count]->{dvb_triplet};
         $CHANNELDATA[$count]->{name} = $tmpchanneldata->[$count]->{channel_name};
         $CHANNELDATA[$count]->{id} = $tmpchanneldata->[$count]->{lcn};
         $CHANNELDATA[$count]->{id} =~ s/[\s\/]//g;
         $CHANNELDATA[$count]->{lcn} = $tmpchanneldata->[$count]->{lcn};
         $CHANNELDATA[$count]->{icon} = $tmpchanneldata->[$count]->{related}->{images}[0]->{url};
         warn("Got channel $CHANNELDATA[$count]->{name} ...\n") if ($VERBOSE);
   }
   return;
};

sub getepg {
   my $showcount = 0;
   foreach my $channel (@CHANNELDATA) {
        my $id = $channel->{dvb_triplet};
        my $lcn = $channel->{lcn};
        warn("Getting epg for $channel->{name} ...\n") if ($VERBOSE);
        my $now = time;
        $now = $now - 86400;
        my $offset;
        for(my $day=0;$day<$NUMDAYS;$day++) { 
           $offset = $day*86400;        
           my ($ssec,$smin,$shour,$smday,$smon,$syear,$swday,$syday,$sisdst) = localtime($now+$offset);
           my ($esec,$emin,$ehour,$emday,$emon,$eyear,$ewday,$eyday,$eisdst) = localtime($now+$offset+86400);
           my $startdate=sprintf("%0.4d-%0.2d-%0.2dT%0.2d:%0.2d:%0.2dZ",($syear+1900),$smon+1,$smday,$shour,$smin,$ssec);
           my $enddate =sprintf("%0.4d-%0.2d-%0.2dT%0.2d:%0.2d:%0.2dZ",($eyear+1900),$emon+1,$emday,$ehour,$emin,$esec);
           warn("\tGetting programs between $startdate and $enddate ...\n") if ($VERBOSE);           
           my $data;
           my $ua = LWP::UserAgent->new;
           my $url = "https://fvau-api-prod.switch.tv/content/v1/epgs/".$id."?start=".$startdate."&end=".$enddate."&sort=start&related_entity_types=episodes.images,shows.images&related_levels=2&include_related=1&expand_related=full&limit=100&offset=0";
           my $res = $ua->get($url);
           if ($res->is_success) {
               $data = $res->content;
           } else {
               die "Unable to connect to FreeView.\n";
           }
           my $tmpdata;
           eval {
              $tmpdata = decode_json($data);
              1;
           };
           $tmpdata = $tmpdata->{data};
           if (defined($tmpdata)) {
           for(my $count=0;$count<@$tmpdata;$count++){
              $GUIDEDATA[$showcount]->{start} = $tmpdata->[$count]->{start};
              $GUIDEDATA[$showcount]->{start} =~ s/[-T:]//g;
              $GUIDEDATA[$showcount]->{start} =~ s/\+/ \+/g;

              $GUIDEDATA[$showcount]->{stop} = $tmpdata->[$count]->{end};
              $GUIDEDATA[$showcount]->{stop} =~ s/[-T:]//g;
              $GUIDEDATA[$showcount]->{stop} =~ s/\+/ \+/g;
              $GUIDEDATA[$showcount]->{channel} = $tmpdata->[$count]->{channel_name};
              $GUIDEDATA[$showcount]->{title} = $tmpdata->[$count]->{related}->{shows}[0]->{title};
              my $catcount = 0;         
              foreach my $tmpcat (@{$tmpdata->[$count]->{related}->{episodes}[0]->{categories}}) {    
                          
                 if ($tmpcat =~ /season_number/) {                     
                     $tmpcat =~ s/season_number\/(.*)/$1/;
                     $GUIDEDATA[$showcount]->{season} = $tmpcat;
                 }
                 if (($tmpcat =~ /content_type\/series/) and (!( grep( /season_number/, @{$tmpdata->[$count]->{related}->{episodes}[0]->{categories}} ) ) ) ) {        
                           my $tmpseries = ToLocalTimeString($tmpdata->[$count]->{start});
                           $tmpseries =~ s/(\d+)-(\d+)-(\d+)T(\d+):(\d+).*/S$1E$2$3$4$5/;                                                                          
                           $GUIDEDATA[$showcount]->{originalairdate} = "$1-$2-$3 $4:$5:00";
                 }
                 $GUIDEDATA[$showcount]->{categories}[$catcount] = $tmpcat;
                 $catcount++;                      
              }
              $GUIDEDATA[$showcount]->{episode} = $tmpdata->[$count]->{related}->{episodes}[0]->{episode_number} if (defined($tmpdata->[$count]->{related}->{episodes}[0]->{episode_number}));              
              $GUIDEDATA[$showcount]->{desc} = $tmpdata->[$count]->{related}->{episodes}[0]->{synopsis};
              $GUIDEDATA[$showcount]->{subtitle} = $tmpdata->[$count]->{related}->{episodes}[0]->{title};
              $GUIDEDATA[$showcount]->{id} = $lcn;
              $GUIDEDATA[$showcount]->{id} =~ s/[\s\/]//g;
              $GUIDEDATA[$showcount]->{url} = $tmpdata->[$count]->{related}->{episodes}[0]->{related}->{images}[0]->{url};
              $showcount++;
           }
           }
        }          
   }
   warn("Processed a totol of $showcount shows ...\n") if ($VERBOSE);   
   return;
}

sub printchannels {
   my ($XMLRef) = @_;
   foreach my $channel (@CHANNELDATA) {
	   $XML->startTag('channel', 'id' => $channel->{id});
	   $XML->dataElement('display-name', $channel->{name});
     $XML->emptyTag('icon', 'src' => $channel->{icon}) if (defined($channel->{icon}));
	   $XML->endTag('channel');   
   }
   return;
}
  
sub printepg {
    my ($XMLRef) = @_;
    foreach my $items (@GUIDEDATA) {
        my $title = $items->{title};
        my $movie = 0;
        my $originalairdate = "";

        $title =~ s/([$chars])/$map{$1}/g;   
        $title =~ s/[^\040-\176]/ /g;
		    ${$XMLRef}->startTag('programme', 'start' => "$items->{start}", 'stop' => "$items->{stop}", 'channel' => "$items->{id}");
		    ${$XMLRef}->dataElement('title', $title);        
        if (defined($items->{subtitle})) {
           my $subtitle = $items->{subtitle};
           $subtitle =~ s/([$chars])/$map{$1}/g;
           ${$XMLRef}->dataElement('sub-title', $subtitle);           
        }
        if (defined($items->{desc})) {
          my $description = $items->{desc};
          $description =~ s/([$chars])/$map{$1}/g;
          $description =~ s/[^\040-\176]/ /g;
          ${$XMLRef}->dataElement('desc', $description);
        }
        foreach my $category (@{$items->{categories}}) {
           if (defined($category)) {
              $category =~ s/([$chars])/$map{$1}/g;
              $category =~ s/[^\040-\176]/ /g;
              ${$XMLRef}->dataElement('category', $category);
           }
        }
        ${$XMLRef}->emptyTag('icon', 'src' => $items->{url}) if (defined($items->{url}));                
        if (defined($items->{season}) && defined($items->{episode})) {
           my $episodeseries = "S".$items->{season}."E".$items->{episode};         
           ${$XMLRef}->dataElement('episode-num', $episodeseries, 'system' => 'SxxExx');
           my $series = $items->{season} - 1;
           my $episode = $items->{episode} - 1;
           $series = 0 if ($series < 0);
           $episode = 0 if ($episode < 0);
           $episodeseries = "$series.$episode.";            
           ${$XMLRef}->dataElement('episode-num', "$series.$episode.", 'system' => 'xmltv_ns');      
        }
        ${$XMLRef}->dataElement('episode-num', $items->{originalairdate}, 'system' => 'original-air-date') if (defined($items->{originalairdate}));  
        ${$XMLRef}->endTag('programme');
    }
    return;
}

sub ToLocalTimeString
{
   my $fulldate = shift;
   my ($year, $month, $day, $hour, $min, $sec, $offset) = $fulldate =~ /(\d+)-(\d+)-(\d+)T(\d+):(\d+):(\d+)(\+.*)/;#S$1E$2$3$4$5$6$7/;
   my ($houroffset, $minoffset) = $offset =~ /(\d+):(\d+)/;    
   my $dt = DateTime->new(
       year       => $year,
       month      => $month,
       day        => $day,
       hour       => $hour,
       minute     => $min,
       second     => $sec,
       nanosecond => 0,
       time_zone  => $offset,
   );
   my $tz = DateTime::TimeZone::Local->TimeZone();
   my $localoffset = $tz->offset_for_datetime(DateTime->now());
   $localoffset = $localoffset/3600;
   if ($localoffset =~ /\./) {
      $localoffset =~ s/(.*)(\..*)/$1$2/;
      $localoffset = sprintf("+%0.2d:%0.2d",$1,($2*60));
   }
   else {
      $localoffset = sprintf("+%0.2d:00",$localoffset);
   }
   $dt->set_time_zone( $tz );
   my $ymd = $dt->ymd;
   my $hms = $dt->hms;
   my $returntime = $ymd."T".$hms.$localoffset;
   return $returntime;
}

sub usage
{
	print "Usage:\n";
	print "\t$0 --region=<region> [--days=<days to collect>] [--pretty] [--output <filename>] [--VERBOSE] [--help|?]\n";
	print "\n\tWhere:\n\n";
  print "\t--region=<region>\tThis defines which tv guide to parse. It is mandatory. Refer below for a list of regions.\n";
  print "\t--days=<days to collect>\tThis defaults to 7 days and can be no more than 7.\n";
	print "\t--pretty\t\tOutput the XML with tabs and newlines to make human readable.\n";
	print "\t--output <filename>\tWrite to the location and file specified instead of standard output\n";
	print "\t--verbose\t\tVerbose Mode (prints processing steps to STDERR).\n";
	print "\t--help\t\t\tWill print this usage and exit!\n";
  print "\t  <region> is one of the following:\n";
  print "\t\t$_\n" foreach(@regions); 
	return "\n";
}