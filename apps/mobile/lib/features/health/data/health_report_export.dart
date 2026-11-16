import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/storage/app_database.dart';
import '../domain/health_metric.dart';
import '../domain/health_report.dart';

class HealthReportExport {
  const HealthReportExport();

  static const disclaimer =
      'اطلاعات ثبت‌شده توسط کاربر/مراقب؛ تأیید پزشکی نشده';

  Future<void> shareCsv({
    required Profile profile,
    required HealthMetric metric,
    required DateTime start,
    required DateTime end,
    required List<HealthMeasurement> records,
  }) async {
    final filename = healthReportFileName(metric, start, end, 'csv');
    final csv = buildHealthCsv(
      profile: profile,
      metric: metric,
      start: start,
      end: end,
      records: records,
    );
    // In-memory bytes are shared through the OS file chooser; no cloud upload.
    await SharePlus.instance.share(ShareParams(
      files: [
        XFile.fromData(
          Uint8List.fromList(utf8.encode(csv)),
          mimeType: 'text/csv',
          name: filename,
        ),
      ],
      fileNameOverrides: [filename],
    ));
  }

  Future<void> sharePdf({
    required Profile profile,
    required HealthMetric metric,
    required DateTime start,
    required DateTime end,
    required List<HealthMeasurement> records,
  }) async {
    final pdf = await buildPdf(
      profile: profile,
      metric: metric,
      start: start,
      end: end,
      records: records,
    );
    await Printing.sharePdf(
      bytes: pdf,
      filename: healthReportFileName(metric, start, end, 'pdf'),
    );
  }

  /// Pure creation except for loading fonts bundled in the application.
  Future<Uint8List> buildPdf({
    required Profile profile,
    required HealthMetric metric,
    required DateTime start,
    required DateTime end,
    required List<HealthMeasurement> records,
  }) async {
    if (records.length > 2000) {
      throw StateError(
        'برای گزارش بیش از ۲۰۰۰ ثبت، بازه کوتاه‌تری انتخاب کنید.',
      );
    }
    final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSansArabic-Bold.ttf'),
    );
    final document = pw.Document();
    const ink = PdfColor(0.10, 0.19, 0.21);
    const teal = PdfColor(0.00, 0.49, 0.46);
    pw.TextStyle style({double size = 10, bool strong = false}) => pw.TextStyle(
          font: strong ? bold : regular,
          fontFallback: [pw.Font.helvetica()],
          fontSize: size,
          color: ink,
        );
    pw.Widget label(String text, {bool strong = false, double size = 10}) =>
        pw.Text(
          text,
          textDirection: pw.TextDirection.rtl,
          style: style(size: size, strong: strong),
        );
    final analysis = HealthReportSummary.calculate(metric, records);
    final dateInfo = 'از ${healthDateTimeLabel(start)} تا '
        '${healthDateTimeLabel(end)}';
    final table = <List<String>>[
      ['تاریخ و ساعت', 'مقدار', 'شرایط', 'یادداشت'],
      for (final entry in records)
        [
          healthDateTimeLabel(entry.observedAt),
          '${HealthNumber.format(entry.primaryMilliunits)}'
              '${entry.secondaryMilliunits == null ? '' : '/${HealthNumber.format(entry.secondaryMilliunits!)}'}'
              ' ${entry.unit}',
          entry.context == null ? '—' : healthContextLabel(entry.context!),
          entry.note?.isNotEmpty == true ? entry.note! : '—',
        ],
    ];
    document.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      maxPages: 200,
      margin: const pw.EdgeInsets.all(30),
      header: (context) => pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 8),
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: teal, width: 1)),
        ),
        child: label('همراه دارو — گزارش اندازه‌گیری'),
      ),
      footer: (context) => pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Divider(color: teal),
          label(disclaimer, size: 9),
        ],
      ),
      build: (context) => [
        pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              label('گزارش ${metric.label}', strong: true, size: 19),
              pw.SizedBox(height: 7),
              label('پروفایل: ${profile.displayName}', strong: true),
              label('بازه (تاریخ میلادی): $dateInfo'),
              label('زمان تولید: ${healthDateTimeLabel(DateTime.now())}'),
              label('تعداد ثبت‌ها: ${records.length}'),
              if (analysis.hasQualityWarning)
                label(
                  '${analysis.excludedCount} ثبت با واحد/شرایط/مقادیر ناقص '
                  'از آمار توصیفی حذف شد؛ در جدول باقی مانده است.',
                ),
              pw.SizedBox(height: 12),
              if (analysis.stats.isEmpty)
                label('در این بازه داده معتبر برای آمار وجود ندارد.')
              else
                for (final group in analysis.stats.entries)
                  label(
                    '${group.key}: ${group.value.count} ثبت، '
                    'کمینه ${HealthNumber.format(group.value.minMilliunits)}، '
                    'بیشینه ${HealthNumber.format(group.value.maxMilliunits)}، '
                    'میانگین توصیفی ${HealthNumber.format(group.value.meanMilliunits)}'
                    ' ${metric.unit}',
                  ),
              pw.SizedBox(height: 13),
              label(
                'جدول ثبت‌ها (بدون تفسیر پزشکی)',
                strong: true,
                size: 13,
              ),
              pw.SizedBox(height: 5),
            ],
          ),
        ),
        if (records.isEmpty)
          label('داده‌ای ثبت نشده است.')
        else
          pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Table.fromTextArray(
              data: table,
              headerCount: 1,
              headerStyle: style(strong: true),
              cellStyle: style(size: 9),
              cellAlignment: pw.Alignment.centerRight,
              cellPadding: const pw.EdgeInsets.all(5),
              border: pw.TableBorder.all(
                color: const PdfColor(0.81, 0.86, 0.88),
                width: 0.4,
              ),
            ),
          ),
        pw.SizedBox(height: 10),
        label('تنها اطلاعات شاخص و پروفایل انتخاب‌شده در گزارش آمده است.'),
      ],
    ));
    return document.save();
  }
}
