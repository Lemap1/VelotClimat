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
          columns: [
            DataColumn(
              label: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                ),
                child: Container(
                  color: Colors.blue.shade50,
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 4,
                  ),
                  child: const Text('Date'),
                ),
              ),
            ),
            const DataColumn(label: Text('Temp')),
            const DataColumn(label: Text('Hum')),
            const DataColumn(label: Text('Lat')),
            const DataColumn(label: Text('Lon')),
            DataColumn(
              label: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(12),
                ),
                child: Container(
                  color: Colors.blue.shade50,
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 4,
                  ),
                  child: const Text('Acc'),
                ),
              ),
            ),
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
