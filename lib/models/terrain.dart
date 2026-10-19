/// Terrain / fuel types a node can be set to. Mirrors worker/src/terrain.ts,
/// which applies each factor to the ML risk probabilities.
class Terrain {
  final String id;
  final String label;
  final double factor;

  const Terrain(this.id, this.label, this.factor);

  static const all = [
    Terrain('pine', 'Pine / conifer forest', 1.8),
    Terrain('eucalyptus', 'Eucalyptus plantation', 1.7),
    Terrain('grassland', 'Grassland / savanna', 1.6),
    Terrain('bamboo', 'Bamboo (moongil) forest', 1.5),
    Terrain('dry_deciduous', 'Dry deciduous (teak, sal)', 1.3),
    Terrain('scrub', 'Scrub / thorn forest', 1.2),
    Terrain('mixed', 'Mixed forest', 1.0),
    Terrain('moist_deciduous', 'Moist deciduous forest', 0.8),
    Terrain('evergreen', 'Tropical evergreen / shola', 0.5),
    Terrain('desert', 'Desert / sparse vegetation', 0.4),
    Terrain('wetland', 'Mangrove / wetland', 0.3),
  ];

  static Terrain byId(String? id) => all.firstWhere(
    (t) => t.id == id,
    orElse: () => all.firstWhere((t) => t.id == 'mixed'),
  );
}
