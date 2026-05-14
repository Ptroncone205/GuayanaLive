import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'pin_detail_screen.dart';
import 'translations.dart';

class PinCluster {
  final double latitude;
  final double longitude;
  final List<Map<String, dynamic>> pins;

  PinCluster({
    required this.latitude,
    required this.longitude,
    required this.pins,
  });
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  Set<Marker> _markers = {};
  Set<Circle> _heatmapCircles = {};
  bool _isLoading = true;
  bool _showHeatmap = true;

  @override
  void initState() {
    super.initState();
    _loadPinsFromSupabase();
  }

  Future<void> _loadPinsFromSupabase() async {
    setState(() => _isLoading = true);
    try {
      final response = await Supabase.instance.client
          .from('pins')
          .select(
            'id, title, image_url, height, created_at, user_id, latitude, longitude, profiles(username, avatar_url)',
          )
          .not('latitude', 'is', null)
          .not('longitude', 'is', null)
          .order('created_at', ascending: false);

      if (response == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final List<dynamic> pinsData = response as List<dynamic>;

      // Obtain tags for the pins so PinDetailScreen works completely
      final pinIds = pinsData.map((pin) => pin['id'] as int).toList();
      final tagRows = pinIds.isEmpty
          ? <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(
              await Supabase.instance.client
                      .from('pin_tags')
                      .select('pin_id, tags(name)')
                      .inFilter('pin_id', pinIds)
                  as List,
            );

      final pinTagsMap = <int, List<String>>{};
      for (final row in tagRows) {
        final pinId = row['pin_id'] as int?;
        final tag =
            ((row['tags'] as Map<String, dynamic>?)?['name']) as String?;
        if (pinId != null && tag != null) {
          pinTagsMap.putIfAbsent(pinId, () => []).add(tag);
        }
      }

      final List<PinCluster> clusters = [];
      const double threshold = 0.005; // Approx 500 meters

      for (var pinData in pinsData) {
        if (pinData['latitude'] != null && pinData['longitude'] != null) {
          final lat = (pinData['latitude'] as num).toDouble();
          final lng = (pinData['longitude'] as num).toDouble();

          final pin = Map<String, dynamic>.from(pinData);
          pin['tags'] = List<String>.from(pinTagsMap[pin['id']] ?? []);

          bool addedToCluster = false;
          for (var cluster in clusters) {
            final distance = sqrt(
              pow(cluster.latitude - lat, 2) + pow(cluster.longitude - lng, 2),
            );
            if (distance < threshold) {
              cluster.pins.add(pin);
              addedToCluster = true;
              break;
            }
          }

          if (!addedToCluster) {
            clusters.add(
              PinCluster(latitude: lat, longitude: lng, pins: [pin]),
            );
          }
        }
      }

      final Set<Marker> newMarkers = {};
      final Set<Circle> newCircles = {};

      for (var cluster in clusters) {
        final lat = cluster.latitude;
        final lng = cluster.longitude;
        final isMultiple = cluster.pins.length > 1;

        newMarkers.add(
          Marker(
            markerId: MarkerId('cluster_${lat}_${lng}'),
            position: LatLng(lat, lng),
            infoWindow: InfoWindow(
              title: isMultiple
                  ? '${cluster.pins.length} ${Translations.text(context, 'sightings')}'
                  : (cluster.pins.first['title']?.toString() ?? Translations.text(context, 'species')),
              snippet:
                  isMultiple ? Translations.text(context, 'tap_to_view_posts') : Translations.text(context, 'tap_to_view_post'),
              onTap: () => _showClusterBottomSheet(cluster.pins),
            ),
          ),
        );

        newCircles.add(
          Circle(
            circleId: CircleId('heat_${lat}_${lng}'),
            center: LatLng(lat, lng),
            radius: 15000,
            fillColor: Colors.red.withOpacity(0.15),
            strokeWidth: 0,
          ),
        );
      }

      if (mounted) {
        setState(() {
          _markers.clear();
          _heatmapCircles.clear();
          _markers.addAll(newMarkers);
          _heatmapCircles.addAll(newCircles);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error cargando marcadores: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Translations.text(context, 'error_loading_markers'))),
        );
      }
    }
  }

  // map_screen.dart (Fragmento actualizado)

  void _showClusterBottomSheet(List<Map<String, dynamic>> pins) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Permite que el panel crezca más
      backgroundColor: Colors.transparent, // Para bordes redondeados
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7, // Panel más alto al abrirse (antes 0.5)
          minChildSize: 0.4, // Altura mínima
          maxChildSize: 0.95, // Casi pantalla completa
          builder: (context, scrollController) {
            // Usamos GestureDetector para capturar gestos y que no lleguen al mapa
            return GestureDetector(
              onVerticalDragUpdate:
                  (_) {}, // Bloquea la propagación vertical al mapa
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  children: [
                    // Indicador visual de arrastre
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 12),
                      height: 5,
                      width: 40,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    Text(
                      '${pins.length} ${Translations.text(context, 'sightings_in_this_zone')}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const Divider(),
                    Expanded(
                      child: GridView.builder(
                        controller:
                            scrollController, // Conectado al scroll del sheet
                        padding: const EdgeInsets.all(10),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                              childAspectRatio: 0.8,
                            ),
                        itemCount: pins.length,
                        itemBuilder: (context, index) {
                          final pin = pins[index];
                          return GestureDetector(
                            onTap: () {
                              // Navegación exacta a la de Pinterest
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      PinDetailScreen(pin: pin),
                                ),
                              );
                            },
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.network(
                                    pin['image_url'] ?? '',
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        Container(color: Colors.grey[200]),
                                  ),
                                  Positioned(
                                    bottom: 0,
                                    left: 0,
                                    right: 0,
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      color: Colors.black54,
                                      child: Text(
                                        pin['title'] ?? Translations.text(context, 'untitled'),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(Translations.text(context, 'sighting_map')),
        actions: [
          Row(
            children: [
              Text(Translations.text(context, 'heat_zones'), style: const TextStyle(fontSize: 12)),
              Switch(
                value: _showHeatmap,
                activeColor: Colors.redAccent,
                onChanged: (val) {
                  setState(() => _showHeatmap = val);
                },
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                color: Theme.of(context).primaryColor,
              ),
            )
          : GoogleMap(
              initialCameraPosition: const CameraPosition(
                target: LatLng(8.29, -62.65),
                zoom: 6,
              ),
              minMaxZoomPreference: const MinMaxZoomPreference(2, 18),
              myLocationEnabled: true,
              markers: _markers,
              circles: _showHeatmap ? _heatmapCircles : {},
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _loadPinsFromSupabase,
        backgroundColor: Theme.of(context).primaryColor,
        tooltip: Translations.text(context, 'update_map'),
        child: const Icon(Icons.refresh, color: Colors.white),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
    );
  }
}
