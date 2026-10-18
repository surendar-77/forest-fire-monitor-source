import 'package:flutter/material.dart';

class LocationCard extends StatelessWidget {
  const LocationCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),

        leading: const Icon(Icons.location_on, size: 30),

        title: const Text(
          'Detected Location',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),

        subtitle: const Text('13.0827° N, 80.2707° E'),

        trailing: IconButton(onPressed: () {}, icon: const Icon(Icons.map)),
      ),
    );
  }
}
