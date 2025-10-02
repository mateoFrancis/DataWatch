import 'package:flutter/material.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Data Watch Homepage',
      home: HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Data Watch'),
        backgroundColor: Colors.blueAccent,
        actions: [
          TextButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => ErrorPage()),
              );
            },
            child: Text("Errors", style: TextStyle(color: Colors.white)),
          ),
          TextButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => LogPage()),
              );
            },
            child: Text("Log", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Data Source Status',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            Table(
              border: TableBorder.all(color: Colors.grey),
              columnWidths: {
                0: FixedColumnWidth(100),
                1: FlexColumnWidth(),
                2: FlexColumnWidth(),
              },
              children: [
                TableRow(
                  decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.2)),
                  children: [
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('Source', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('Connection', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('Report Submission', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                _buildStatusRow('Source A', Icons.check, Icons.warning),
                _buildStatusRow('Source B', Icons.close, Icons.more_horiz),
                _buildStatusRow('Source C', Icons.check, Icons.check),
              ],
            ),
            Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.black, width: 1),
                    borderRadius: BorderRadius.circular(4),
                    color: Colors.white,
                  ),
                  padding: EdgeInsets.all(8),
                  margin: EdgeInsets.only(bottom: 8, right: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Legend',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 8),
                      _buildLegendRow(Icons.check, 'OK'),
                      _buildLegendRow(Icons.close, 'Error'),
                      _buildLegendRow(Icons.warning, 'Issue'),
                      _buildLegendRow(Icons.more_horiz, 'Stale/Processing'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        color: Colors.blueAccent,
        height: 40,
        child: SizedBox(
          height: 40,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Padding(
                padding: EdgeInsets.only(left: 12),
                child: Text(
                  'Data Watch',
                  style: TextStyle(color: Colors.black, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  TableRow _buildStatusRow(String source, IconData connectionIcon, IconData reportIcon) {
    return TableRow(
      children: [
        Padding(
          padding: EdgeInsets.all(8),
          child: Text(source),
        ),
        Padding(
          padding: EdgeInsets.all(8),
          child: Icon(connectionIcon, color: _getIconColor(connectionIcon)),
        ),
        Padding(
          padding: EdgeInsets.all(8),
          child: Icon(reportIcon, color: _getIconColor(reportIcon)),
        ),
      ],
    );
  }

  Widget _buildLegendRow(IconData icon, String label) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 18, color: _getIconColor(icon)),
          SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }

  Color _getIconColor(IconData icon) {
    if (icon == Icons.check) return Colors.green;
    if (icon == Icons.close) return Colors.red;
    if (icon == Icons.warning) return Colors.orange;
    return Colors.grey; // for Icons.more_horiz
  }
}

// Mock data for Errors
final List<Map<String, String>> errorEntries = [
  {
    'time': '2025-10-02 13:09',
    'description': 'Sensor dropout detected',
    'status': 'Unresolved',
  },
  {
    'time': '2025-10-02 12:45',
    'description': 'Voltage spike on Node A',
    'status': 'Investigating',
  },
];

// Mock data for Logs
final List<Map<String, String>> logEntries = [
  {
    'time': '2025-10-02 12:00',
    'description': 'System initialized',
    'status': 'OK',
  },
  {
    'time': '2025-10-02 12:30',
    'description': 'Heartbeat received from Node B',
    'status': 'OK',
  },
];

class ErrorPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Errors')),
      body: ListView.builder(
        itemCount: errorEntries.length,
        itemBuilder: (context, index) {
          final entry = errorEntries[index];
          return Card(
            margin: EdgeInsets.all(10),
            child: ListTile(
              title: Text(entry['description'] ?? ''),
              subtitle: Text('Time: ${entry['time']}\nStatus: ${entry['status']}'),
            ),
          );
        },
      ),
    );
  }
}

class LogPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Log')),
      body: ListView.builder(
        itemCount: logEntries.length,
        itemBuilder: (context, index) {
          final entry = logEntries[index];
          return Card(
            margin: EdgeInsets.all(10),
            child: ListTile(
              title: Text(entry['description'] ?? ''),
              subtitle: Text('Time: ${entry['time']}\nStatus: ${entry['status']}'),
            ),
          );
        },
      ),
    );
  }
}


