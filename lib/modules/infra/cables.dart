import '../../data/reference_data.dart';

/// Réseau d'un câble, déduit du catalogue (`MAT_CABLE.CAB_TYPE`).
enum Network { telecom, energy, unknown }

/// Style d'une flèche de la rosace (légende Hirondelle) : couleur = réseau, tireté = branchement.
class CableStyle {
  const CableStyle(this.network, {required this.drop});

  final Network network;
  final bool drop;

  static CableStyle of(ReferenceData ref, int? matKey) {
    final c = ref.cable(matKey);
    final type = c?['CAB_TYPE'] as String?;
    final network = switch (type) {
      'N' || 'I' => Network.energy,
      'Telecom' || 'FO' || 'Fibre' => Network.telecom,
      _ => Network.unknown,
    };
    return CableStyle(network, drop: c?['CAB_USAGE'] == 'BRANCHEMENT');
  }
}

/// Tensions de pose des câbles portés (`INF_PORTEE_CABLE.PCB_TENSION`).
const voltages = {
  'STD_AGGLO': 'Standard agglomération', // tr
  'STD_ECART': 'Standard écart', // tr
  'RELEVE': 'Flèche relevée', // tr
};
