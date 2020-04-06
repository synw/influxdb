import 'package:meta/meta.dart';

/// A database row
class InfluxRow {
  /// Default constructor
  const InfluxRow(
      {@required this.fields,
      this.time,
      this.tags = const <String, dynamic>{},
      this.table});

  /// The time field
  final DateTime time;

  /// The field set
  final Map<String, dynamic> fields;

  /// The tags set
  final Map<String, dynamic> tags;

  /// The table number in query results
  final int table;

  /// Convert this to an Influxdb line protocol string
  ///
  /// Provide a [measurement]
  /// Set [withTimestamp] to false to not include a timestamp.
  /// The default timestamp used is the value of this [time]
  /// If [time] is null a timestamp is generated
  String toLineProtocol(String measurement, {bool withTimestamp = true}) {
    final _f = <String>[];
    fields.forEach((key, dynamic value) {
      if (value is String) {
        _f.add('$key="$value"');
      } else {
        _f.add('$key=$value');
      }
    });
    final _t = <String>[];
    tags.forEach((key, dynamic value) {
      _t.add('$key=$value');
    });
    var _ts = "";
    if (withTimestamp) {
      if (time != null) {
        _ts = " ${time.microsecondsSinceEpoch * 1000}";
      } else {
        _ts = " ${DateTime.now().microsecondsSinceEpoch * 1000}";
      }
    }
    return "$measurement,${_t.join(",")} ${_f.join(",")}${_ts}";
  }

  @override
  String toString() {
    return "$time ${fields.length} fields, ${tags.length} tags";
  }

  /// Get detailled info about this row
  String details() {
    /* print("------------");
    print("D TAGS: ${tags.keys.toList()[0]} / ${tags.values.toList()[0]}");
    print("------------");*/
    var s = "$time\n";
    s += "Fields:\n";
    fields.forEach((key, dynamic value) {
      s += "- $key : $value\n";
    });
    if (tags.keys.isNotEmpty) {
      s += "Tags:\n";
      tags.forEach((k, dynamic v) {
        s += "- $k : $v\n";
        print("------------");
        print("k = $k");
        print("v = $v");
        print("------------");
      });
    }
    return s;
  }
}
