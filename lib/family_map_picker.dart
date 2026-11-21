import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import 'phone_actions.dart';
import 'place.dart';

class FamilyMapPicker extends StatefulWidget {
  const FamilyMapPicker({super.key});
  @override
  State<FamilyMapPicker> createState() => _FamilyMapPickerState();
}

class _FamilyMapPickerState extends State<FamilyMapPicker> {
  final map = MapController();
  final query = TextEditingController();
  LatLng? point;
  LatLng? deviceLocation;
  bool busy = false;
  String? error;
  @override
  void dispose() {
    map.dispose();
    query.dispose();
    super.dispose();
  }

  Future<void> locateMe() async {
    if (busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await DevicePhoneActions().locate(freshOnly: true);
      if (!mounted) return;
      if (result is LocationFound) {
        final place = result.place;
        final position = LatLng(place.latitude, place.longitude);
        deviceLocation = position;
        point = position;
        query.text = place.address ?? '';
        map.move(position, 18);
      } else {
        error = switch (result) {
          LocationOff() => '請開啟手機定位，或直接點選地圖',
          LocationDenied() => '未取得定位權限，可搜尋地址或點選地圖',
          _ => '暫時無法取得目前位置，請再試一次或點選地圖',
        };
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> search() async {
    if (busy || query.text.trim().isEmpty) return;
    final text = query.text.trim();
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      point = null;
      error = null;
    });
    try {
      final results = await Geocoding()
          .locationFromAddress(
            RegExp(r'^(台灣|臺灣|台澎金馬|Taiwan)', caseSensitive: false).hasMatch(text)
                ? text
                : '台灣 $text',
            locale: const Locale('zh', 'TW'),
          )
          .timeout(const Duration(seconds: 8));
      if (!mounted) return;
      final points = results
          .map((r) => LatLng(r.latitude, r.longitude))
          .toSet()
          .toList();
      final origin = deviceLocation;
      if (origin != null) {
        const distance = Distance();
        points.sort(
          (a, b) => distance(origin, a).compareTo(distance(origin, b)),
        );
      }
      if (points.isEmpty) {
        error = '找不到符合的地址，請加上縣市或路名';
        return;
      }
      final matches = await Future.wait(
        points
            .take(5)
            .map(
              (p) async => (
                p,
                await DevicePhoneActions().addressAt(p.latitude, p.longitude),
              ),
            ),
      );
      if (!mounted) return;
      final chosen = await showModalBottomSheet<LatLng>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  '選擇搜尋結果',
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
              ),
              for (final (p, address) in matches)
                ListTile(
                  leading: const Icon(Icons.place_outlined),
                  title: Text(address ?? '查看地圖位置'),
                  subtitle: Text(
                    '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}',
                  ),
                  onTap: () => Navigator.pop(ctx, p),
                ),
            ],
          ),
        ),
      );
      if (!mounted || chosen == null) return;
      point = chosen;
      map.move(chosen, 18);
    } catch (_) {
      if (mounted) error = '查不到地址，可直接點選地圖';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> confirm() async {
    final selected = point;
    if (busy || selected == null) return;
    setState(() => busy = true);
    final address = await DevicePhoneActions().addressAt(
      selected.latitude,
      selected.longitude,
    );
    if (mounted) {
      Navigator.pop(
        context,
        address ??
            '${selected.latitude.toStringAsFixed(6)}, ${selected.longitude.toStringAsFixed(6)}',
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('從地圖選'),
      actions: [
        TextButton.icon(
          onPressed: busy ? null : locateMe,
          icon: const Icon(Icons.my_location),
          label: const Text('我的位置'),
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: query,
              enabled: !busy,
              onChanged: (_) {
                if (point != null || error != null) {
                  setState(() {
                    point = null;
                    error = null;
                  });
                }
              },
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => search(),
              decoration: InputDecoration(
                labelText: '搜尋台灣地址',
                hintText: '縣市、路名、門牌',
                errorText: error,
                suffixIcon: IconButton(
                  tooltip: '搜尋',
                  onPressed: busy ? null : search,
                  icon: const Icon(Icons.search),
                ),
              ),
            ),
          ),
          Expanded(
            child: FlutterMap(
              mapController: map,
              options: MapOptions(
                initialCenter: const LatLng(23.7, 120.95),
                initialZoom: 7,
                onTap: (_, p) {
                  if (!busy) {
                    setState(() {
                      point = p;
                      error = null;
                    });
                  }
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.anxinban.app',
                ),
                if (deviceLocation != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: deviceLocation!,
                        width: 18,
                        height: 18,
                        child: const DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                            border: Border.fromBorderSide(
                              BorderSide(color: Colors.white, width: 2),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                if (point != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: point!,
                        alignment: Alignment.topCenter,
                        child: const Icon(Icons.location_on, color: Colors.red),
                      ),
                    ],
                  ),
                RichAttributionWidget(
                  showFlutterMapAttribution: false,
                  attributions: [
                    TextSourceAttribution(
                      'OpenStreetMap contributors',
                      onTap: () => launchUrl(
                        Uri.parse('https://www.openstreetmap.org/copyright'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              onPressed: busy || point == null ? null : confirm,
              child: Text(
                busy
                    ? '處理中…'
                    : point == null
                    ? '請點選地圖上的位置'
                    : '使用這個地點',
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
