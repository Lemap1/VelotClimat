import 'package:flutter/material.dart';

class LogTable extends StatelessWidget {
  final List<String> csvLines;
  const LogTable({super.key, required this.csvLines});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(Colors.blue.shade50),
          columns: const [
            DataColumn(label: Text('Date')),
            DataColumn(label: Text('Temp')),
            DataColumn(label: Text('Hum')),
            DataColumn(label: Text('Lat')),
            DataColumn(label: Text('Long')),
            DataColumn(label: Text('Acc')),
          ],
          rows: csvLines
              .skip(1) // skip header
              .where((line) => line.trim().isNotEmpty)
              .toList()
              .reversed // latest first
              .map((line) {
                final cells = line.split(',');
                while (cells.length < 6) {
                  cells.add('--');
                }
                return DataRow(
                  cells: [
                    DataCell(Text(cells[0])),
                    DataCell(
                      Text(
                        cells[1],
                        style: TextStyle(color: Colors.orange.shade700),
                      ),
                    ),
                    DataCell(
                      Text(
                        cells[2],
                        style: TextStyle(color: Colors.blue.shade700),
                      ),
                    ),
                    DataCell(
                      Text(
                        cells[3],
                        style: TextStyle(color: Colors.green.shade700),
                      ),
                    ),
                    DataCell(
                      Text(
                        cells[4],
                        style: TextStyle(color: Colors.green.shade700),
                      ),
                    ),
                    DataCell(
                      Text(
                        cells[5],
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    ),
                  ],
                );
              })
              .toList(),
        ),
      ),
    );
  }
}
