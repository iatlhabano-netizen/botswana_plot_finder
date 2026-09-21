import 'package:latlong2/latlong.dart' as ll;
import 'package:url_launcher/url_launcher.dart';

class ExternalMaps {
  static Future<void> openNavigation(ll.LatLng pt) async {
    final nav = Uri.parse(
        'google.navigation:q=${pt.latitude},${pt.longitude}');
    final web = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${pt.latitude},${pt.longitude}');
    if (await canLaunchUrl(nav)) {
      await launchUrl(nav);
    } else {
      await launchUrl(web, mode: LaunchMode.externalApplication);
    }
  }

  static Future<void> openView(ll.LatLng pt) async {
    final geo = Uri.parse('geo:${pt.latitude},${pt.longitude}?q=${pt.latitude},${pt.longitude}');
    final web = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${pt.latitude},${pt.longitude}');
    if (await canLaunchUrl(geo)) {
      await launchUrl(geo);
    } else {
      await launchUrl(web, mode: LaunchMode.externalApplication);
    }
  }
}
