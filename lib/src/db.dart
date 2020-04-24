import 'dart:async';

import 'package:dio/dio.dart';
import 'package:meta/meta.dart';
import 'package:pedantic/pedantic.dart';

import 'models.dart';

final _dio = Dio();

/// A client for Influxdb
class InfluxDb {
  /// Main constructor
  InfluxDb({
    @required this.address,
    @required this.token,
    @required this.org,
    this.bucket,
    this.batchInterval = 300,
  });

  /// The Influxdb database address
  final String address;

  /// The Influxdb org
  final String org;

  /// The Influxdb token
  final String token;

  /// The Influxdb default bucket to use
  String bucket;

  /// The interval to post batch data in milliseconds
  final int batchInterval;

  final _writeQueue = <String>[];
  var _isQueueRunning = false;
  Timer _queueTimer;

  /// Write an [InfluxRow] to the database
  Future<void> write(InfluxRow row,
      {@required String measurement,
      String toBucket,
      bool verbose = false}) async {
    String b;
    try {
      b = _getBucket(toBucket);
    } catch (e) {
      rethrow;
    }
    await _postWrite(row.toLineProtocol(measurement), b, verbose: verbose);
  }

  /// Write line protocol data to the database
  Future<void> writeLine(String line,
      {@required String measurement,
      String toBucket,
      bool verbose = false}) async {
    String b;
    try {
      b = _getBucket(toBucket);
    } catch (e) {
      rethrow;
    }
    await _postWrite(line, b, verbose: verbose);
  }

  /// Push an [InfluxRow] into the write queue
  Future<void> push(InfluxRow row,
      {@required String measurement, bool verbose = false}) async {
    if (bucket == null) {
      throw ArgumentError.notNull(
          "Please set the default bucket before pushing to the write queue");
    }
    if (!_isQueueRunning) {
      unawaited(_runWriteQueue(verbose: verbose));
      _isQueueRunning = true;
    }
    _writeQueue.add(row.toLineProtocol(measurement));
  }

  /// Run a read query
  Future<List<InfluxRow>> select(
      {@required String start,
      @required String measurement,
      String fromBucket,
      String stop,
      List<String> groupBy,
      int limit,
      bool verbose = false}) async {
    String b;
    try {
      b = _getBucket(fromBucket);
    } catch (e) {
      rethrow;
    }
    var q = 'from(bucket:"$b") |> range(start: $start';
    if (stop != null) {
      q += ', stop: $stop';
    }
    q += ')';
    q += ' |> filter(fn: (r) => r._measurement == "$measurement")';
    if (groupBy != null) {
      q += ' |> group(columns: [' + groupBy.join(",") + '])';
    }
    if (limit != null) {
      q += ' |> limit(n:$limit)';
    }
    // post to api
    final dynamic resp = await _postQuery(q, verbose: verbose);
    // process result
    final raw = resp.toString().split("\n");
    return _processRawData(raw);
  }

  /// Count data in a bucket from a field name
  Future<Map<String, int>> countMeasurements(String field,
      {@required String start,
      String fromBucket,
      String stop,
      bool verbose = false}) async {
    String b;
    try {
      b = _getBucket(fromBucket);
    } catch (e) {
      rethrow;
    }
    var q = 'from(bucket:"$b") |> range(start: $start';
    if (stop != null) {
      q += ', stop: $stop';
    }
    q += ')';
    q += ' |> filter(fn: (r) => r["_field"] == "$field")';
    q += '|> count()';
    // post to api
    final dynamic resp = await _postQuery(q, verbose: verbose);
    final raw = resp.toString().split("\n");
    final res = <String, int>{};
    raw.forEach((line) {
      print(line);
      if (line.startsWith(",_result")) {
        final l = line.split(",");
        final m = l[6];
        final v = l.last;
        res[m] = int.parse(v);
      }
    });
    return res;
  }

  /// Show all the measurements in a bucket
  Future<List<String>> measurements(
      {String inBucket, String timeRange = "-1h", bool verbose = false}) async {
    String b;
    try {
      b = _getBucket(inBucket);
    } catch (e) {
      rethrow;
    }
    final q = 'from(bucket:"$b")'
        '|> range(start:$timeRange)'
        '|> keep(columns: ["_measurement"])'
        '|> distinct()';
    final dynamic res = await _postQuery(q, verbose: verbose);
    final l = List<String>.from((res as String).split("\n"));
    final m = <String>[];
    for (final row in l.sublist(1)) {
      final el = row.split(",");
      if (el.length != 5) {
        continue;
      }
      final v = el[3];
      m.add(v);
    }
    return m;
  }

  /// Stop the write queue if started
  void stopQueue() {
    if (_isQueueRunning) {
      _queueTimer.cancel();
    }
  }

  /// Dispose the class when finished using
  void dispose() => stopQueue();

  List<InfluxRow> _processRawData(List<String> data) {
    final rmap = <DateTime, InfluxRow>{};
    final headers = data[0];
    for (final line in data.sublist(1)) {
      if (line.isNotEmpty) {
        if (line != "\n") {
          //print(line);
          if (line.startsWith(
              ",result,table,_start,_stop,_time,_value,_field,_measurement")) {
            //print("HEADER $line");
            continue;
          }
          /*const spliter = "##*/ /*##";
          final li = line.replaceFirst(measurement, spliter);
          final l = li.split(spliter);*/

          final tmpl = line.split(",");
          if (tmpl.length < 2) {
            continue;
          }
          final fieldsList = tmpl.sublist(0, 8);
          final measurement = tmpl[8];
          //final tagsList = tmpl.sublist(9);
          final table = int.parse(fieldsList[2]);
          final time = DateTime.parse(fieldsList[5]);
          final dynamic value = fieldsList[6];
          final field = fieldsList[7].replaceFirst(",", "");
          // tags
          final tags = <String>[];
          final tagLine = headers.replaceFirst(
              ",result,table,_start,_stop,_time,_value,_field,_measurement,",
              "");
          final tagNames = <String>[];
          if (tagLine.length > 1) {
            tagNames.addAll(tagLine.split(","));
          } else {
            tagNames.add(tagLine);
          }
          //tagNames.forEach((element) => print("TN $element"));
          final tagsMap = <String, dynamic>{};
          var i = 0;
          //print("TN 0 : ${tagNames[0]}");
          tags.forEach((v) {
            tagsMap[tagNames[i]] = v;
            ++i;
          });
          // row
          if (!rmap.containsKey(time)) {
            rmap[time] = InfluxRow(
                measurement: measurement,
                table: table,
                fields: <String, dynamic>{field: value},
                tags: tagsMap,
                time: time);
          } else {
            final r = rmap[time];
            final f = r.fields;
            f[field] = value;
            final row = InfluxRow(
                measurement: measurement,
                table: r.table,
                fields: f,
                tags: r.tags,
                time: r.time);
            rmap[time] = row;
          }
        }
      }
    }
    return rmap.values.toList();
  }

  Future<dynamic> _postQuery(String data, {@required bool verbose}) async {
    if (verbose) {
      print(data);
    }
    dynamic resp;
    try {
      final addr = "$address/api/v2/query";
      final response = await _dio.post<dynamic>(addr,
          options: Options(
            headers: <String, dynamic>{"Authorization": "Token $token"},
            contentType: "application/vnd.flux",
          ),
          queryParameters: <String, dynamic>{"org": org, "bucket": bucket},
          data: data);
      if (response.statusCode == 200) {
        resp = response.data;
      } else {
        throw Exception("Wrong status code: ${response.statusCode}");
      }
    } on DioError catch (e) {
      if (e.response != null) {
        print(e.response.data);
        print(e.response.headers);
        print(e.response.request);
      } else {
        print(e.request);
        print(e.message);
      }
    } catch (e) {
      rethrow;
    }
    return resp;
  }

  Future<void> _postWrite(String data, String toBucket,
      {@required bool verbose}) async {
    String b;
    try {
      b = _getBucket(toBucket);
    } catch (e) {
      rethrow;
    }
    if (verbose) {
      print(data);
    }
    try {
      final addr = "$address/api/v2/write";
      await _dio.post<dynamic>(addr,
          options: Options(
            headers: <String, dynamic>{"Authorization": "Token $token"},
            contentType: "text/plain; charset=utf-8",
          ),
          queryParameters: <String, dynamic>{"org": org, "bucket": b},
          data: data);
      //print("RESP: ${resp.statusCode} \n$resp");
    } on DioError catch (e) {
      // The request was made and the server responded with a status code
      // that falls out of the range of 2xx and is also not 304.
      if (e.response != null) {
        print(e.response.data);
        print(e.response.headers);
        print(e.response.request);
      } else {
        // Something happened in setting up or sending the request that triggered an Error
        print(e.request);
        print(e.message);
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _runWriteQueue({@required bool verbose}) async {
    if (verbose) {
      print("Running write queue for bucket $bucket");
    }
    _queueTimer =
        Timer.periodic(Duration(milliseconds: batchInterval), (t) async {
      if (_writeQueue.isNotEmpty) {
        if (verbose) {
          print("Queue: writing ${_writeQueue.length} datapoints");
        }
        await _postWrite(_writeQueue.join("\n"), bucket, verbose: verbose);
        _writeQueue.clear();
      }
    });
  }

  String _getBucket(String b) {
    if (b == null) {
      if (bucket == null) {
        throw ArgumentError.notNull(
            "Please provide a bucket parameter or set the default bucket");
      } else {
        return bucket;
      }
    }
    return b;
  }
}
