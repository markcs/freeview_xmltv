#!/usr/bin/perl
use strict;
use warnings;
use JSON;
use DateTime;
use Getopt::Long;
use LWP::UserAgent;

my $debug = 0;
my $numdays = 7;
my %map = (
    '&' => 'and',
);
my $chars = join '', keys %map;

my @channeldata;
my @guidedata;
my $region;
my $outputfile;
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
    
GetOptions(
    'region=s'    => \$region,
    'file=s'      => \$outputfile,
) or die "Incorrect usage!\n";

if ((!defined($region)) || (!defined($outputfile))) {
        print "\nPlease use the command.\n\tfree_epg.pl --region=<REGION-NAME> --file=<output xmltv filename>.\n\n\tREGION-NAME is one of the following:\n";
        print "\t\t$_\n" foreach(@regions);
        print "\n";
        exit();      
}

elsif (defined($region)) {
    if (!( grep( /^$region$/, @regions ) ) ) {
        print "\nInvalid region specified.  Please use one of the following:\n";
        print "\t\t$_\n" foreach(@regions);
        exit();
    }
}

getchannels();
getepg();
open(my $fh, '>:encoding(UTF-8)', $outputfile) or die "Could not create the file '$outputfile' $!";
print $fh "<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>\n<!DOCTYPE tv SYSTEM \"xmltv.dtd\">\n";
print $fh "<tv generator-info-url=\"http://www.xmltv.org/\">\n";
printchannels();
printepg();
print $fh "</tv>\n";
exit();


sub getchannels {
   my $data;
   my $ua = LWP::UserAgent->new;
   my $res = $ua->get('https://fvau-api-prod.switch.tv/content/v1/channels/region/$region?limit=100&offset=0&include_related=1&expand_related=full&related_entity_types=images');
   if ($res->is_success) {
       $data = $res->content;
       print "$data\n" if ($debug);
   } else {
      die "Unable to connect to FreeView.\n";
   }
   my $tmpchanneldata = decode_json($data);   
   $tmpchanneldata = $tmpchanneldata->{data};
   for(my $count=0;$count<@$tmpchanneldata;$count++){
         $channeldata[$count]->{dvb_triplet} = $tmpchanneldata->[$count]->{dvb_triplet};
         $channeldata[$count]->{name} = $tmpchanneldata->[$count]->{channel_name};
         $channeldata[$count]->{id} = $tmpchanneldata->[$count]->{lcn}.".".$tmpchanneldata->[$count]->{channel_name};
         $channeldata[$count]->{id} =~ s/[\s\/]//g;
         $channeldata[$count]->{lcn} = $tmpchanneldata->[$count]->{lcn};
         $channeldata[$count]->{icon} = $tmpchanneldata->[$count]->{related}->{images}[0]->{url};
   }
   return;
};

sub getepg {
   my $showcount = 0;
   foreach my $channel (@channeldata) {
      my $id = $channel->{dvb_triplet};
      my $lcn = $channel->{lcn};
        my $now = time;
        $now = $now - 86400;
        my $offset;
        for(my $day=0;$day<$numdays;$day++) { 
           $offset = $day*86400;        
           my ($ssec,$smin,$shour,$smday,$smon,$syear,$swday,$syday,$sisdst) = localtime($now+$offset);
           my ($esec,$emin,$ehour,$emday,$emon,$eyear,$ewday,$eyday,$eisdst) = localtime($now+$offset+86400);
           my $startdate=sprintf("%0.4d-%0.2d-%0.2dT%0.2d:%0.2d:%0.2dZ",($syear+1900),$smon+1,$smday,$shour,$smin,$ssec);
           my $enddate =sprintf("%0.4d-%0.2d-%0.2dT%0.2d:%0.2d:%0.2dZ",($eyear+1900),$emon+1,$emday,$ehour,$emin,$esec);
           print "https://fvau-api-prod.switch.tv/content/v1/epgs/".$id."?start=".$startdate."&end=".$enddate."&sort=start&related_entity_types=episodes.images,shows.images&related_levels=2&include_related=1&expand_related=full&limit=100&offset=0\n" if ($debug);
           my $data;
           my $ua = LWP::UserAgent->new;
           my $url = "https://fvau-api-prod.switch.tv/content/v1/epgs/".$id."?start=".$startdate."&end=".$enddate."&sort=start&related_entity_types=episodes.images,shows.images&related_levels=2&include_related=1&expand_related=full&limit=100&offset=0";
           my $res = $ua->get($url);
           if ($res->is_success) {
               $data = $res->content;
               print "$data\n" if ($debug);
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
              $guidedata[$showcount]->{start} = $tmpdata->[$count]->{start};
              $guidedata[$showcount]->{start} =~ s/[-T:]//g;
              $guidedata[$showcount]->{start} =~ s/\+/ \+/g;

              $guidedata[$showcount]->{stop} = $tmpdata->[$count]->{end};
              $guidedata[$showcount]->{stop} =~ s/[-T:]//g;
              $guidedata[$showcount]->{stop} =~ s/\+/ \+/g;
              $guidedata[$showcount]->{channel} = $tmpdata->[$count]->{channel_name};
              $guidedata[$showcount]->{title} = $tmpdata->[$count]->{related}->{shows}[0]->{title};
              my $catcount = 0;         
              foreach my $tmpcat (@{$tmpdata->[$count]->{related}->{episodes}[0]->{categories}}) {    
                          
                 if ($tmpcat =~ /season_number/) {                     
                     $tmpcat =~ s/season_number\/(.*)/$1/;
                     $guidedata[$showcount]->{season} = $tmpcat;
                 }
                 if (($tmpcat =~ /content_type\/series/) and (!( grep( /season_number/, @{$tmpdata->[$count]->{related}->{episodes}[0]->{categories}} ) ) ) ) {        
                           my $tmpseries = ToLocalTimeString($tmpdata->[$count]->{start});
                           $tmpseries =~ s/(\d+)-(\d+)-(\d+)T(\d+):(\d+).*/S$1E$2$3$4$5/;                                                                          
                           $guidedata[$showcount]->{originalairdate} = "$1-$2-$3 $4:$5:00";
                 }
                 $guidedata[$showcount]->{categories}[$catcount] = $tmpcat;
                 $catcount++;                      
              }
              $guidedata[$showcount]->{episode} = $tmpdata->[$count]->{related}->{episodes}[0]->{episode_number} if (defined($tmpdata->[$count]->{related}->{episodes}[0]->{episode_number}));              
              $guidedata[$showcount]->{desc} = $tmpdata->[$count]->{related}->{episodes}[0]->{synopsis};
              $guidedata[$showcount]->{subtitle} = $tmpdata->[$count]->{related}->{episodes}[0]->{title};
              $guidedata[$showcount]->{id} = $lcn.".".$tmpdata->[$count]->{channel_name};
              $guidedata[$showcount]->{id} =~ s/[\s\/]//g;
              $guidedata[$showcount]->{url} = $tmpdata->[$count]->{related}->{episodes}[0]->{related}->{images}[0]->{url};
              $showcount++;
           }
           }
        }          
   }
   
   print "Shows retreived: $showcount\n" if ($debug);
   return;
}

sub printchannels {
   foreach my $channel (@channeldata) {
     print $fh "\t<channel id=\"".$channel->{id}."\">\n";
     print $fh "\t\t<display-name>".$channel->{name}."</display-name>\n";
     print $fh "\t\t<icon src=\"".$channel->{icon}."\" />\n" if (defined($channel->{icon}));
     print $fh "\t</channel>\n";
   }
   return;
}
  
sub printepg {
    foreach my $items (@guidedata) {
        my $title = $items->{title};
        my $movie = 0;
        my $originalairdate = "";

        $title =~ s/([$chars])/$map{$1}/g;   
        $title =~ s/[^\040-\176]/ /g;     
        print $fh "\t<programme start=\"$items->{start}\" stop=\"$items->{stop}\" channel=\"$items->{id}\">\n";
        print $fh "\t\t<title>".$title."</title>\n";
        if (defined($items->{subtitle})) {
           my $subtitle = $items->{subtitle};
           $subtitle =~ s/([$chars])/$map{$1}/g;
           print $fh "\t\t<sub-title>".$subtitle."</sub-title>\n";
        }
        if (defined($items->{desc})) {
          my $description = $items->{desc};
          $description =~ s/([$chars])/$map{$1}/g;
          $description =~ s/[^\040-\176]/ /g;
          print $fh "\t\t<desc>".$description."</desc>\n" ;
        }
        foreach my $category (@{$items->{categories}}) {
           if (defined($category)) {
              $category =~ s/([$chars])/$map{$1}/g;
              $category =~ s/[^\040-\176]/ /g;
              print $fh "\t\t<category lang=\"en\">$category</category>\n" if defined($category);
           }
        }
        
        print $fh "\t\t<icon src=\"$items->{url}\" />\n" if (defined($items->{url}));                
        if (defined($items->{season}) && defined($items->{episode})) {
           print $fh "\t\t<episode-num system=\"SxxExx\">S$items->{season}E$items->{episode}</episode-num>\n";
           my $series = $items->{season} - 1;
           my $episode = $items->{episode} - 1;
           $series = 0 if ($series < 0);
           $episode = 0 if ($episode < 0);
           print $fh "\t\t<episode-num system=\"xmltv_ns\">$series.$episode.</episode-num>\n"
           
        }
        print $fh "\t\t<episode-num system=\"original-air-date\">$items->{originalairdate}</episode-num>\n" if (defined($items->{originalairdate}));        
        print $fh "\t</programme>\n";
    }
    return;
}

sub ToLocalTimeString
{
   my $fulldate = shift;
   my ($year, $month, $day, $hour, $min, $sec, $offset) = $fulldate =~ /(\d+)-(\d+)-(\d+)T(\d+):(\d+):(\d+)(\+.*)/;#S$1E$2$3$4$5$6$7/;
   print "$fulldate -> $year, $month, $day, $hour, $min, $sec, $offset\n" if ($debug);
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
   print "Local tz0: $localoffset\n" if ($debug);
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
   print "DT2 -> ".$dt->hms."\n" if ($debug);
   my $returntime = $ymd."T".$hms.$localoffset;
   return $returntime;
}