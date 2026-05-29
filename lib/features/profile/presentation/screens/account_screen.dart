import 'package:flutter/material.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _PlaceholderProfileModule(title: 'Account');
  }
}

class _PlaceholderProfileModule extends StatelessWidget {
  const _PlaceholderProfileModule({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF4F5F7),
      body: SafeArea(child: Center(child: Text(title))),
    );
  }
}
