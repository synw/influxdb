import 'package:influxdb/influxdb.dart';
import 'package:binance/binance.dart';
import 'package:pedantic/pedantic.dart';

import 'conf.dart' as conf;

Future<void> main(List<String> args) async {
  final db = InfluxDb(
      address: conf.dbAddress,
      org: conf.dbOrg,
      token: conf.dbToken,
      bucket: conf.dbBucket);
  if (args.isNotEmpty) {
    if (args[0] == "-w") {
      print("Writing data");
      await write(db);
    }
  } else {
    print("Reading data");
    await read(db);
  }
}

const symbol = "BTCUSDT";
const timeFrame = "-1h";
const limit = 1;

Future<void> read(InfluxDb db) async {
  final rows =
      await db.select(start: timeFrame, measurement: symbol, limit: limit);
  rows.forEach((row) => print(row.details()));
}

Future<void> write(InfluxDb db) async {
  final _binance = Binance();
  // grab some data from the Binance api
  _binance.aggTrade(symbol).listen((trade) {
    // create a row
    final row = InfluxRow(
      measurement: symbol,
      time: trade.time,
      fields: <String, dynamic>{
        "amount": trade.qty,
        "price": trade.price,
      },
      tags: <String, dynamic>{
        "maker_side": trade.isBuyerMaker ? "buy" : "sell",
      },
    );
    // push to the write queue
    unawaited(db.push(row, measurement: symbol, verbose: true));
  });
}
