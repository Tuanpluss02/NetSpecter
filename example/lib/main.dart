import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:netspecter/netspecter.dart';

void main() {
  final dio = Dio()..interceptors.add(NetSpecterDioInterceptor());

  runApp(NetSpecterExampleApp(dio: dio));
}

class NetSpecterExampleApp extends StatelessWidget {
  const NetSpecterExampleApp({super.key, required this.dio});

  final Dio dio;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NetSpecter Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      home: NetSpecterOverlay(child: ExampleHomePage(dio: dio)),
    );
  }
}

class ExampleHomePage extends StatefulWidget {
  const ExampleHomePage({super.key, required this.dio});

  final Dio dio;

  @override
  State<ExampleHomePage> createState() => _ExampleHomePageState();
}

class _ExampleHomePageState extends State<ExampleHomePage> {
  String _status = 'Tap a button to generate network traffic.';
  bool _isLoading = false;

  Future<void> _runRequest(
    String label,
    Future<Response<dynamic>> Function() action,
  ) async {
    setState(() {
      _isLoading = true;
      _status = 'Running $label...';
    });

    try {
      final response = await action();
      if (!mounted) {
        return;
      }

      setState(() {
        _status = '$label complete: ${response.statusCode}';
      });
    } on DioException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _status = '$label failed: ${error.message}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<Response<dynamic>> _sendGet() {
    return widget.dio.get<dynamic>(
      'https://jsonplaceholder.typicode.com/posts/1',
    );
  }

  Future<Response<dynamic>> _sendPost() {
    return widget.dio.post<dynamic>(
      'https://jsonplaceholder.typicode.com/posts',
      data: <String, Object?>{
        'title': 'NetSpecter',
        'body': 'Smoke test payload',
        'userId': 1,
      },
    );
  }

  Future<Response<dynamic>> _sendServerError() {
    return widget.dio.get<dynamic>('https://httpstat.us/503');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('NetSpecter Example')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(_status, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _isLoading
                  ? null
                  : () => _runRequest('GET request', _sendGet),
              child: const Text('Send GET'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _isLoading
                  ? null
                  : () => _runRequest('POST request', _sendPost),
              child: const Text('Send POST'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _isLoading
                  ? null
                  : () => _runRequest('Error request', _sendServerError),
              child: const Text('Send Error Request'),
            ),
            const SizedBox(height: 24),
            const Text(
              'Use the floating network button to open the inspector after generating traffic.',
            ),
          ],
        ),
      ),
    );
  }
}
