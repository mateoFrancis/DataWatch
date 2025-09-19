import 'package:flutter/material.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Data Watch Homepage',
      home: Scaffold(
        appBar: AppBar(
          title: Text('Data Watch'),
          backgroundColor: Colors.blueAccent,
          actions: [
            TextButton(
              onPressed: () {
                // Handle Errors button Press Here
              },
              child: Text("Errors", style: TextStyle(color: Colors.white)),
            ),
            TextButton(
              onPressed: () {
                // Handle Log Button press
              }, 
              child: Text("Log", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
        body: Center(
          child: Text(
            'Data Paths Go Here',
            style: TextStyle(fontSize: 24),
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
                Text(
                  'Data Watch',
                  textAlign: TextAlign.left,
                  style: TextStyle(color: Colors.black, fontSize: 14),
                ),
                TextButton(
                  onPressed: () {
                    // Handle Simplistic View press here
                  },
                  child: Text("Simplistic View Button", style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  }