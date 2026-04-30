import 'package:flutter/material.dart';

class WorkoutCard extends StatelessWidget {
  const WorkoutCard({
    super.key,
    required this.program,
    required this.description,
    required this.date,
  });

  final String program;
  final String description;
  final String date;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              program,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(date),
            const SizedBox(height: 10),
            Text(description),
          ],
        ),
      ),
    );
  }
}
