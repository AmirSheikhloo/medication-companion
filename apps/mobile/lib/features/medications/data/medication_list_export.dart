import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_text_shaper/pdf_text_shaper.dart';
import 'package:printing/printing.dart';

import '../../../core/calendar/persian_date.dart';
import '../../../core/storage/app_database.dart';
import 'medication_repository.dart';

/// A locally built, patient-controlled PDF. No network service is involved.
class MedicationListExport {
  const MedicationListExport();

  Future<void> sharePdf({
    required Profile profile,
    required List<Medication> medications,
    required List<DailyDose> doses,
    required DateTime forDay,
  }) async {
    final bytes = await buildPdf(
      profile: profile,
      medications: medications,
      doses: doses,
      forDay: forDay,
    );
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'medication-list-'
          '${forDay.year}${forDay.month.toString().padLeft(2, '0')}'
          '${forDay.day.toString().padLeft(2, '0')}.pdf',
    );
  }

  Future<Uint8List> buildPdf({
    required Profile profile,
    required List<Medication> medications,
    required List<DailyDose> doses,
    required DateTime forDay,
  }) async {
    if (medications.length > 200 || doses.length > 2400) {
      throw StateError('برای خروجی PDF، تعداد داروها بیش از حد مجاز است.');
    }
    final ids = medications.map((m) => m.id).toSet();
    if (ids.length != medications.length ||
        medications.any((m) => m.profileId != profile.id || m.archived) ||
        doses.any((d) => d.medication.profileId != profile.id ||
            !ids.contains(d.medication.id))) {
      throw StateError('اطلاعات گزارش فقط باید متعلق به همین پروفایل باشد.');
    }

    final regular = ShapedFont.fromBytes((await rootBundle.load(
      'assets/fonts/NotoSansArabic-Regular.ttf')).buffer.asUint8List());
    final bold = ShapedFont.fromBytes((await rootBundle.load(
      'assets/fonts/NotoSansArabic-Bold.ttf')).buffer.asUint8List());
    const teal = PdfColor(0.03, 0.37, 0.38);
    final doc = pw.Document();
    pw.Widget label(String value, {bool strong = false, double size = 13}) =>
        ShapedText(
          PersianDate.persianDigits(value),
          style: ShapedTextStyle(
            font: strong ? bold : regular,
            fontSize: size,
            direction: AnyPdfTextDirection.rightToLeft,
            align: AnyPdfTextAlign.end,
          ),
        );
    final sortedMeds = [...medications]
      ..sort((a, b) => a.name.compareTo(b.name));
    try {
      doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(30),
      maxPages: 100,
      header: (context) => pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 8),
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: teal, width: 1)),
        ),
        child: label('همراه دارو — فهرست داروها برای پزشک',
            strong: true, size: 13),
      ),
      footer: (context) => pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Divider(color: teal),
          label('اطلاعات واردشده توسط کاربر است و تأیید پزشکی نشده.', size: 11),
        ],
      ),
      build: (context) => [
        pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              label('فهرست داروهای فعال', strong: true, size: 22),
              pw.SizedBox(height: 8),
              label('پروفایل: ${profile.displayName}', strong: true),
              label('برنامهٔ روز: ${persianDateLabel(forDay)} (شمسی)'),
              label('زمان تهیهٔ گزارش: ${persianDateLabel(DateTime.now(), showTime: true)}'),
              label('تعداد داروها: ${medications.length}'),
              pw.SizedBox(height: 12),
            ],
          ),
        ),
        if (sortedMeds.isEmpty)
          label('داروی فعالی ثبت نشده است.')
        else
          for (final medicine in sortedMeds)
            pw.Container(
              width: double.infinity,
              margin: const pw.EdgeInsets.only(bottom: 9),
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: const PdfColor(0.82, 0.88, 0.88)),
              ),
              child: pw.Directionality(
                textDirection: pw.TextDirection.rtl,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    label(medicine.name, strong: true, size: 17),
                    pw.SizedBox(height: 5),
                    if (!doses.any((d) => d.medication.id == medicine.id))
                      label('برای این تاریخ نوبتی ثبت نشده است.')
                    else
                      for (final dose in doses.where((d) =>
                          d.medication.id == medicine.id))
                        label('${dose.scheduledAt.hour.toString().padLeft(2, '0')}:'
                            '${dose.scheduledAt.minute.toString().padLeft(2, '0')}'
                            ' — ${dose.plan.doseText}'),
                  ],
                ),
              ),
            ),
        pw.SizedBox(height: 12),
        label('این فهرست فقط برنامهٔ ثبت‌شده برای تاریخ فوق است؛ '
            'برنامهٔ ویرایش‌شده ممکن است از فردا اعمال شود.'),
      ],
      ));
      return await doc.save();
    } finally {
      regular.dispose();
      bold.dispose();
    }
  }
}
