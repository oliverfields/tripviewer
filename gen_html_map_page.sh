#!/bin/bash
# Create web page for showing map with photo markers and gpx route

# Settings
lib_dir="$1"
dist_dir='dist'
dist_media_dir="$dist_dir/media"
dist_media_thumb_dir="$dist_media_dir/thumbnails"
thumbnail_size="40x40"
source_media_dir="$PWD/media"

declare -A required_files
required_files['settings']="settings.json"
required_files['track']="track.gpx"
required_files['gps_locations']="gps_locations_file_lat_lon.csv"

# Check required files exist
for i in "${!required_files[@]}"; do
	f="${required_files[$i]}"
	[ ! -e "$f" ] && echo "Unable to find $f, initializing from '$lib_dir/$f'" && cp "$lib_dir/$f" "$f"
done

# Check media directory exists
[ ! -d "$source_media_dir" ] && echo "Creating media directory" && mkdir "$source_media_dir"

if [ -e "$dist_dir" ]; then
	rm -Rf "$dist_dir"
fi

mkdir "$dist_dir"
cp -R "$lib_dir"/js "$dist_dir"/.
cp -R "$lib_dir"/css "$dist_dir"/.
cp -R "$lib_dir"/images "$dist_dir"/.
cp track.gpx "$dist_dir"/.
cp -R "$lib_dir"/webfonts "$dist_dir"/.

mkdir "$dist_media_dir"
mkdir "$dist_media_thumb_dir"

# Create json and image files to use to add markers
function prepare_media() {
	json=""
	total_files="$(ls -1 "$source_media_dir" | wc -l)"
	progress_counter=1

	# For media files get their location and create stuff for making markers
	for m in "$source_media_dir"/*; do
		name="${m##*/}"
		file_name="${name##.*}"
		extension="${m##*.}"
		extension="${extension,,}" # convert to lower case
		lat=""
		lon=""

		progress_percent="$(bc -l <<< "scale=2; $progress_counter/$total_files" | sed 's/^0\.//')"
		progress_percent="${progress_percent:1}"
		progress_percent="${progress_percent#0}"

		if [ "$progress_counter" = "1" ]; then
			progress_percent=0
		fi
		if [ "$progress_percent" = ".00" ]; then
			progress_percent="100"
		fi
		#echo "$progress_percent% ($progress_counter / $total_files)" >&2
		echo -ne "\e[0K\rProcessing: $progress_percent% ($progress_counter/$total_files): $name" >&2
		let "progress_counter++"

		# Get lat lon from file_lat_lon.csv if defined
		IFS=',' read -r file lat lon <<<"$(grep "^$name," ${required_files["gps_locations"]})"
		if [ "$lat" != "" -a "$lon" != "" ]; then
			: # Do nothing
		else
			# Try to get GPS info directly from file exif info
			latlon="$(exiftool -GPSPosition -s -s -s -c "%+.6f" "$m" | sed 's/\ //g ; s/N// ; s/S// ; s/\ //g')" # Perhaps a hack, but only need to track if E og W for lat, sed just gets rid of N and S from coordinates

			lat="${latlon%,*}"
			lon="${latlon#*,}"
		fi

		if [ "$lat" == "" -a "$lon" == "" ]; then
			echo "WARNING: No gps location found: $m" >&2
			# Skip to next media file
			continue
		else
			latlon_json="\"lat\": $lat, \"lon\": $lon, "
		fi

		case $extension in
			jpg|jpeg|JPG|JPEG)
				thumbnail_file="$dist_media_thumb_dir/$name"
				# Rotate according to exif info
				exiftran -a -o "$dist_media_dir/$name" "$m"
				cp "$dist_media_dir/$name" "$thumbnail_file"
				# Optimize image for web viewing
				mogrify -quiet -resize 1920x1080\> "$dist_media_dir/$name"
			;;
			mov|MOV|mp4|MP4)
				cp "$m" "$dist_media_dir/"
				thumbnail_file="$dist_media_thumb_dir/$file_name.jpg"
				# Extract first frame from thumbnail
				ffmpeg -i "$dist_media_dir/$name" -hide_banner -loglevel panic -vf "select=eq(n\,0)" -q:v 1 "$thumbnail_file"
			;;
			*)
				echo "ERROR: Unknown extension for $m, quitting" >&2
				exit 1
			;;
		esac



		# Create thumbnail
		convert "$thumbnail_file" -resize "$thumbnail_size^" -gravity center -crop $thumbnail_size+0+0 +repage "$thumbnail_file"


		# Strip exif data
		exiftool -q -overwrite_original -all= "$dist_media_dir/$name"

		json="$json{"
		json="${json}$latlon_json"
		json="$json\"thumb\": \"${thumbnail_file#dist/}\", "
		json="$json\"src\": \"${dist_media_dir#dist/}/$name\""
		json="$json},"

	done

	echo -e "\e[0K\rProcessing: 100%" >&2
	echo "" >&2 #New line after progress info

	# Trim last comma [,]
	json="${json%?}"

	echo "[$json]"
}

page_title="$(grep '"page_title":' ${required_files["settings"]} | sed 's/",$// ; s/.*"//g')"
title_image="$(grep '"title_image":' ${required_files["settings"]} | sed 's/",$// ; s/.*"//g')"

media_json="$(prepare_media)"

#Create favicon & FB share html
if [ -e "$source_media_dir/$title_image" ]; then

	exiftran -a -o tmp_image "$source_media_dir/$title_image" # Rotate by exif
	convert tmp_image -set option:distort:viewport "%[fx:min(w,h)]x%[fx:min(w,h)]" -distort affine "%[fx:w>h?(w-h)/2:0],%[fx:w<h?(h-w)/2:0] 0,0" tmp_image
	convert tmp_image -resize 32x32 "$dist_dir"/favicon.ico
	rm tmp_image

	fb_share_html="<meta property=\"og:title\" content=\"$page_title\">
<meta property=\"og:image\" content=\"media/$title_image\">"
fi

# Create download archive
#cwd="$PWD"
#cd "$dist_media_dir"
#zip -r -q --exclude=\*thumbnails\* download.zip .
#cd "$cwd"
#mv "$dist_media_dir"/download.zip "$dist_dir"


settings="$(<${required_files["settings"]})"


cat <<PAGEHTML > "$dist_dir"/index.html
<!DOCTYPE html>
<html>
	<head>
		<meta charset="utf-8">
		<meta name="viewport" content="width=device-width, initial-scale=1">
		$fb_share_html
		<title>$page_title</title>
		<link rel="shortcut icon" href="favicon.ico">

		<link rel="stylesheet" href="css/leaflet.css" />
		<link rel="stylesheet" href="css/easy-button.css" />
		<link rel="stylesheet" href="css/all.min.css" />
		<link rel="stylesheet" href="css/leaflet.awesome-markers.css">
		<link rel="stylesheet" href="css/L.Control.MapCenterCoord.min.css" />


		<style>
*, body {
margin: 0;
padding: 0;
font-family: sans-serif;
}
#map {
height: 100%;
width:100%;
top: 0;
left: 0;
position: absolute;
}
#download_form {
display: none;
}
.leaflet-marker-icon {
border: solid 1px white;
}
		</style>
	</head>
	<body>
		<script src="js/leaflet-src.js"></script>
		<script src="js/gpx.min.js"></script>
		<script src="js/easy-button.js"></script>
		<script src='js/leaflet.awesome-markers.min.js'></script>
		<script src="js/L.Control.MapCenterCoord.min.js"></script>

		<div id="map"></div>
		<!--
		<form id="download_form" method="get" name="download" action="download.zip"><button type="submit">Download</button></form>
		-->
		<script>

var settings = $settings;
//document.title = settings['page_title'];

var OpenTopoMap = L.tileLayer('https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png', {
    maxZoom: 20,
    attribution: 'Map data: &copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors, <a href="http://viewfinderpanoramas.org">SRTM</a> | Map style: &copy; <a href="https://opentopomap.org">OpenTopoMap</a> (<a href="https://creativecommons.org/licenses/by-sa/3.0/">CC-BY-SA</a>)'
});

var esriAerialUrl = 'https://server.arcgisonline.com/ArcGIS/rest/services'+
'/World_Imagery/MapServer/tile/{z}/{y}/{x}';
var esriAerialAttrib = 'Tiles &copy; Esri &mdash; Source: Esri, i-cubed, '+
'USDA, USGS, AEX, GeoEye, Getmapping, Aerogrid, IGN, IGP, UPR-EGP, and the'+
' GIS User Community';
var esriAerial = new L.TileLayer(esriAerialUrl,
    {maxZoom: 15, attribution: esriAerialAttrib});

var markers = L.layerGroup();
var media = L.layerGroup();
var track = L.layerGroup();

var map = new L.Map('map', {
    center: [settings["map_initial_latitude"], settings["map_initial_longitude"]],
    zoom: settings["map_initial_zoom"],
    zoomControl: true,
    layers: [OpenTopoMap, markers, media, track],
//    enableHighAccurac: true,
//    watch: true
});

var gpx = 'track.gpx';
new L.GPX(gpx, {async: true, polyline_options: {
    color: 'red',
    opacity: 0.75,
    weight: 3,
    lineCap: 'round'
  }}).on('loaded', function(e) {
  map.fitBounds(e.target.getBounds());
}).addTo(track);


// Coordinate viewer
//https://github.com/xguaita/Leaflet.MapCenterCoord
L.control.mapCenterCoord().addTo(map);

var media_json = $media_json;

for (var i = 0; i < media_json.length; i++) {

	var thumbIcon = L.icon({
		iconUrl: media_json[i]['thumb'],
		iconSize: [40, 40],
		iconAnchor:   [20, 20], // point of the icon which will correspond to marker's location
		shadowUrl: 'images/thumb-shadow.png',
		shadowSize:   [30, 22], // size of the shadow
		shadowAnchor: [-8, 0],  // the same for the shadow
	});

	L.marker(
		[media_json[i]['lat'], media_json[i]['lon']],
		{icon: thumbIcon}
	).addTo(media).on('click', function(e) {open_media(this);});
}

// Get click event and use onclick event to figure out what json src url to open based on thumbnail src url
function open_media(obj){
	for (var i = 0; i < media_json.length; i++) {
		if(obj['_icon']['src'].endsWith(media_json[i]['thumb'])) {
			window.open(media_json[i]['src']);
			break;
		}
	}
}

// Add custom markers from settings
for (var i = 0; i < settings['markers'].length; i++) {
	var lat = settings['markers'][i]['lat'];
	var lon = settings['markers'][i]['lon'];
	var name = settings['markers'][i]['name'];
	var icon = settings['markers'][i]['icon'];

	var awesome_marker_options = L.AwesomeMarkers.icon({
		prefix: 'fa',
		icon: icon,
		markerColor: 'blue'
	});

	var marker = L.marker([lat, lon], {icon: awesome_marker_options}).addTo(markers);
	var popup = marker.bindPopup('<strong>' + name + '</strong>');
}

var baseMaps = {
	"Topo": OpenTopoMap,
	"Aerial": esriAerial
};

var overlays = {
	"POIs": markers,
	"Media content": media,
	"Track": track
}

L.control.layers(baseMaps, overlays).addTo(map);

/*
L.easyButton(
	'fa-download',
	function(btn, map){
		document.download.submit();
	},
	'Download media content'
).addTo(map);
*/
		</script>
	</body>
</html>
PAGEHTML