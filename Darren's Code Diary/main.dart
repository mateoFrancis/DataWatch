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

class HomePage extends StatefulWidget {
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<Map<String, dynamic>> sources = [
    {
      'name': 'Source A',
      'connection': Icons.check,
      'report': Icons.warning,
      'connectionDetails': 'Last checked: 2025-10-06 14:12\nConnection stable.',
      'reportDetails': 'Last submitted: 2025-10-06 13:45\nWarning: Submission delayed due to queue overflow.',
    },
    {
      'name': 'Source B',
      'connection': Icons.close,
      'report': Icons.more_horiz,
      'connectionDetails': 'Last checked: 2025-10-06 12:30\nError: Node unreachable.',
      'reportDetails': 'Last submitted: 2025-10-06 11:50\nStale: Awaiting new data.',
    },
    {
      'name': 'Source C',
      'connection': Icons.check,
      'report': Icons.check,
      'connectionDetails': 'Last checked: 2025-10-06 15:05\nConnection healthy.',
      'reportDetails': 'Last submitted: 2025-10-06 15:00\nReport received successfully.',
    },
  ];

  final Map<String, bool> expandedConnection = {};
  final Map<String, bool> expandedReport = {};

  @override
  void initState() {
    super.initState();
    for (var source in sources) {
      expandedConnection[source['name']] = false;
      expandedReport[source['name']] = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Data Watch'),
        backgroundColor: Colors.blueAccent,
        actions: [
          TextButton(
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => ErrorPage()));
            },
            child: Text("Errors", style: TextStyle(color: Colors.white, fontSize: 16)),
          ),
          TextButton(
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => LogPage()));
            },
            child: Text("Log", style: TextStyle(color: Colors.white, fontSize: 16)),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Data Source Status', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            SizedBox(height: 20),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black, width: 2),
                borderRadius: BorderRadius.circular(8),
                color: Colors.white,
              ),
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      SizedBox(width: 140),
                      Expanded(
                        child: Center(
                          child: Text('Connection', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: Text('Report Submission', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                        ),
                      ),
                    ],
                  ),
                  Divider(color: Colors.black),
                  ...sources.map((source) {
                    final name = source['name'];
                    return Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              SizedBox(
                                width: 140,
                                child: Text(name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                              ),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () {
                                    setState(() {
                                      expandedConnection[name] = !expandedConnection[name]!;
                                    });
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: Colors.black,
                                    side: BorderSide(color: Colors.black),
                                    padding: EdgeInsets.symmetric(vertical: 18, horizontal: 24),
                                  ),
                                  child: Icon(source['connection'], color: _getIconColor(source['connection']), size: 30),
                                ),
                              ),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () {
                                    setState(() {
                                      expandedReport[name] = !expandedReport[name]!;
                                    });
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: Colors.black,
                                    side: BorderSide(color: Colors.black),
                                    padding: EdgeInsets.symmetric(vertical: 18, horizontal: 24),
                                  ),
                                  child: Icon(source['report'], color: _getIconColor(source['report']), size: 30),
                                ),
                              ),
                            ],
                          ),
                          if (expandedConnection[name]!)
                            Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(source['connectionDetails'], style: TextStyle(fontSize: 16)),
                              ),
                            ),
                          if (expandedReport[name]!)
                            Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Text(source['reportDetails'], style: TextStyle(fontSize: 16)),
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
            Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.black, width: 2),
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.white,
                  ),
                  padding: EdgeInsets.all(16),
                  margin: EdgeInsets.only(bottom: 12, right: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Legend', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                      SizedBox(height: 12),
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
        height: 50,
        child: SizedBox(
          height: 50,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Padding(
                padding: EdgeInsets.only(left: 16),
                child: Text('Data Watch', style: TextStyle(color: Colors.black, fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLegendRow(IconData icon, String label) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 24, color: _getIconColor(icon)),
          SizedBox(width: 12),
          Text(label, style: TextStyle(fontSize: 18)),
        ],
      ),
    );
  }

  Color _getIconColor(IconData icon) {
    if (icon == Icons.check) return Colors.green;
    if (icon == Icons.close) return Colors.red;
    if (icon == Icons.warning) return Colors.orange;
    return Colors.grey;
  }
}

class ErrorPage extends StatelessWidget {
  final List<Map<String, String>> errorEntries = [
    {'time': '2025-10-02 13:09', 'description': 'Sensor dropout detected', 'status': 'Unresolved'},
    {'time': '2025-10-02 12:45', 'description': 'Voltage spike on Node A', 'status': 'Investigating'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Errors')),
      body: ListView.builder(
        itemCount: errorEntries.length,
        itemBuilder: (context, index) {
          final entry = errorEntries[index];
          return Card(
            margin: EdgeInsets.all(12),
            child: ListTile(
              title: Text(entry['description'] ?? '', style: TextStyle(fontSize: 18)),
              subtitle: Text('Time: ${entry['time']}\nStatus: ${entry['status']}', style: TextStyle(fontSize: 16)),
            ),
          );
        },
      ),
    );
  }
}

class LogPage extends StatelessWidget {
  final List<Map<String, String>> logEntries = [
    {'time': '2025-10-02 12:00', 'description': 'System initialized', 'status': 'OK'},
    {'time': '2025-10-02 12:30', 'description': 'Heartbeat received from Node B', 'status': 'OK'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Log')),
      body: ListView.builder(
        itemCount: logEntries.length,
        itemBuilder: (context, index) {
          final entry = logEntries[index];
          return Card(
            margin: EdgeInsets.all(12),
            child: ListTile(
              title: Text(entry['description'] ?? '', style: TextStyle(fontSize: 18)),
              subtitle: Text('Time: ${entry['time']}\nStatus: ${entry['status']}', style: TextStyle(fontSize: 16)),
            ),
          );
        },
      ),
    );
  }
}


