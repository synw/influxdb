# Influxdb

Influxdb 2 client for Dart

## Usage

### Initialize

   ```dart
   final db = InfluxDb(
      address: "http://localhost:9999",
      org: "my_org",
      token: "a_database_token",
      bucket: "the_bucket_to_use");
   ```

### Read data

   ```dart
   final List<InfluxRow> rows = await db.select(
      start: "-20m", stop: "-30m", measurement: "my_measurement");
   ```

Structure of an `InfluxRow`:

   ```dart
  final DateTime time;
  final Map<String, dynamic> fields;
  final Map<String, dynamic> tags;
  final int table;
   ```

### Write data

Define a datapoint:

   ```dart
   final row = InfluxRow(
      time: DateTime.parse("2020-04-06 09:49:18.156Z"),
      fields: <String, dynamic>{
        "amount": 340,
        "price": 2653.5,
      },
      tags: <String, dynamic>{
        "side": "ask",
      },
    );
   ```

#### Write a single datapoint

   ```dart
  await db.write(row, measurement: "my_measurement");
   ```

#### Write a datapoint in Influxdb line protocol

   ```dart
   // it is possible to convert data from a row:
   final line = row.toLineProtocol("my_measurement")
   // post to api
   await db.writeLine(line, measurement: "my_measurement");
   ```

#### Batch write

Push a datapoint to the write queue:

   ```dart
  await db.push(row, measurement: "my_measurement");
   ```

By default the queue will post to the api every 300 milliseconds. This can be configured:

   ```dart
   final db = InfluxDb(
      // ...
      batchInterval: 500
   );
   ```

## Run the example

Create a `example/bin/conf.dart` file:

   ```dart
   const String dbAddress = "http://localhost:9999";
   const String dbToken = "my_token";
   const String dbOrg = "my_org";
   const String dbBucket = "the_bucket_to_use";
   ```

Write some data: `dart bin/main.dart -w`

Read the data: `dart bin/main.dart`