#!/bin/bash
# Create web page for showing map with photo markers and gpx route

# Settings
dist_dir='dist'
dist_media_dir="$dist_dir/media"
dist_media_thumb_dir="$dist_media_dir/thumbnails"
thumbnail_size="40x40"

if [ -e "$dist_dir" ]; then
	rm -Rf "$dist_dir"
fi
mkdir "$dist_dir"
cp -R js "$dist_dir"/.
cp -R css "$dist_dir"/.
cp -R images "$dist_dir"/.
cp track.gpx "$dist_dir"/.
cp -R webfonts "$dist_dir"/.
cp favicon.ico "$dist_dir"/.

mkdir "$dist_media_dir"
mkdir "$dist_media_thumb_dir"


# Create json and image files to use to add markers
function prepare_media() {
	json=""

	# For media files get their location and create stuff for making markers
	for m in media/*; do
		name="${m##*/}"
		file_name="${name##.*}"
		extension="${m##*.}"
		extension="${extension,,}" # convert to lower case
		lat=""
		lon=""

		# Get lat lon from file_lat_lon.csv if defined
		IFS=',' read -r file lat lon <<<"$(grep "^$name," file_lat_lon.csv)"
		if [ "$lat" != "" -a "$lon" != "" ]; then
			: # Do nothing
		else
			# Try to get GPS info directly from file exif info
			latlon="$(exiftool -GPSPosition -s -s -s -c "%+.6f" "$m" | sed 's/\ //g ; s/N// ; s/S// ; s/\ //g')" # Perhaps a hack, but only need to track if E og W for lat, sed just gets rid of N and S from coordinates

			lat="${latlon%,*}"
			lon="${latlon#*,}"

			# If lon is W then prefix it with -
			#if [ "${lon: -1}" = "W" ]; then
			#	lon="-${lon::-1}"
			#elif [ "${lon: -1}" = "E" ]; then
			#	lon="${lon::-1}"
			#fi
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

		# Resize all thumbnails
		for t in "$dist_media_thumb_dir/"*; do
			convert "$t" -resize "$thumbnail_size^" -gravity center -crop $thumbnail_size+0+0 +repage "$t"
		done

		json="$json{"
		json="${json}$latlon_json"
		json="$json\"thumb\": \"${thumbnail_file#dist/}\", "
		json="$json\"src\": \"${dist_media_dir#dist/}/$name\""
		json="$json},"

	done

	# Trim last comma [,]
	json="${json%?}"

	echo "[$json]"
}

media_json="$(prepare_media)"

# Create download archive
#cwd="$PWD"
#cd "$dist_media_dir"
#zip -r -q --exclude=\*thumbnails\* download.zip .
#cd "$cwd"
#mv "$dist_media_dir"/download.zip "$dist_dir"

# Optimize media files
shopt -s nocaseglob # Enable case insensitive globbing
# Reduce image size
mogrify -quiet -resize 1920x1080\> "$dist_media_dir"/*.jpg > /dev/null 2>&1
mogrify -quiet -resize 1920x1080\> "$dist_media_dir"/*.jpeg > /dev/null 2>&1
# Strip exif data
exiftool -q -all= *.jpg > /dev/null 2>&1
exiftool -q -all= *.jpeg > /dev/null 2>&1
exiftool -q -all= *.mov > /dev/null 2>&1
shopt -u nocaseglob

settings="$(<settings.json)"


cat <<PAGEHTML > "$dist_dir"/index.html
<!DOCTYPE html>
<html>
	<head>
		<meta charset="utf-8">
		<meta name="viewport" content="width=device-width, initial-scale=1">
		<title>Trip viewer</title>
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
document.title = settings['page_title'];

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
		shadowAnchor: [-5, 1],  // the same for the shadow
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