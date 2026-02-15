import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

const logoAsset = 'assets/images/logo.png';
const iconPrefix = 'assets/images/icons/';

Future<void> readConfig() async {
  await rootBundle.loadString('assets/json/config.json');
  await rootBundle.load('assets/yaml/missing_runtime.yaml');
  await http.get(Uri.parse('https://example.com'));
}

void main() {
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            Image.asset('assets/images/used.png'),
            Image.asset(logoAsset),
            Image.asset('${iconPrefix}home.png'),
            const Text(
              'fixture',
              style: TextStyle(fontFamily: 'AppFont'),
            ),
          ],
        ),
      ),
    ),
  );
}
