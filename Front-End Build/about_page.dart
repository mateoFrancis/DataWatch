import 'package:flutter/material.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  // Team members in the requested order
  static const List<Map<String, String>> _team = [
    {
      'name': 'Darren Benavides',
      'email': 'd.ben70599@gmail.com'
    },
    {
      'name': 'Francis Mateo-Lazo',
      'email': 'mateofrancis2003@gmail.com'
    },
    {
      'name': 'Francisco Serrato',
      'email': 'fs_2002@proton.me'
    },
    {
      'name': 'Russell Barreyro',
      'email': 'rubarreyro81@gmail.com'
    },
    {
      'name': 'David Ayeni',
      'email': 'david.timi@icloud.com'
    },
  ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    // On narrow screens show a single column (stacked). On wider screens show 3 columns.
    final int crossAxisCount = width < 600 ? 1 : 3;
    // Adjust card height/width ratio to taste
    final double childAspectRatio = width < 600 ? 5 / 1.4 : 3 / 1.2;

    return Scaffold(
      appBar: AppBar(
        title: const Text('About Us'),
        backgroundColor: Colors.blueAccent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'About DataWatch',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            const Text(
              'DataWatch is a monitoring platform that tracks and visualizes data source connectivity and reporting performance in real time. '
              'It helps teams detect system issues early, analyze logs, and maintain operational transparency across distributed systems.',
              style: TextStyle(fontSize: 18, height: 1.4),
            ),
            const SizedBox(height: 20),
            const Text(
              'Version 0.2.0 — Developed 2025',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
            const SizedBox(height: 28),

            // Team header
            const Text(
              'Team',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),

            // Responsive grid: 3 on wide screens, 1 on narrow (mobile)
            GridView.count(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: childAspectRatio,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: List.generate(_team.length, (index) {
                final member = _team[index];
                return Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Avatar or initials
                        CircleAvatar(
                          radius: 26,
                          backgroundColor: Colors.blueAccent.shade100,
                          child: Text(
                            _initials(member['name'] ?? ''),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Details
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                member['name'] ?? '',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                member['phone'] ?? '',
                                style: const TextStyle(fontSize: 14, color: Colors.black87),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                member['email'] != null && member['email']!.isNotEmpty
                                    ? member['email']!
                                    : 'Email not provided',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: member['email'] != null && member['email']!.isNotEmpty
                                      ? Colors.blueGrey
                                      : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),

            const SizedBox(height: 24),
            // Optional footer or additional info
            const Text(
              'Contact the team for support or questions about DataWatch.',
              style: TextStyle(fontSize: 14, color: Colors.black87),
            ),
          ],
        ),
      ),
    );
  }

  // Helper to produce initials for avatar
  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }
}
