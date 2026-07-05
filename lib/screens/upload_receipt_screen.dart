import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';
import '../services/receipt_service.dart';
import '../services/receipt_parser.dart';
import 'receipt_review_screen.dart';

class UploadReceiptScreen extends StatefulWidget {
  const UploadReceiptScreen({super.key});

  @override
  State<UploadReceiptScreen> createState() => _UploadReceiptScreenState();
}

class _UploadReceiptScreenState extends State<UploadReceiptScreen> {
  final ImagePicker _picker = ImagePicker();
  final ReceiptService _receiptService = ReceiptService();

  File? _selectedImage;
  bool _isUploading = false;
  bool _isScanning = false;
  String? _errorMessage;

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: source,
        imageQuality: 80,
      );
      if (picked == null) return;

      final compressedFile = await _compressImage(File(picked.path));

      setState(() {
        _selectedImage = compressedFile;
        _errorMessage = null;
      });
    } catch (e) {
      setState(() => _errorMessage = 'Could not access camera/gallery: $e');
    }
  }

  /// Compresses the picked image to cut storage usage.
  /// Targets 1080px on the long edge at 70% quality — enough for viewing
  /// and OCR while being far smaller than a raw camera photo.
  Future<File> _compressImage(File original) async {
    final tempDir = await getTemporaryDirectory();
    final targetPath =
        '${tempDir.path}/receipt_${DateTime.now().millisecondsSinceEpoch}.jpg';

    final result = await FlutterImageCompress.compressAndGetFile(
      original.absolute.path,
      targetPath,
      quality: 70,
      minWidth: 1080,
      minHeight: 1080,
      format: CompressFormat.jpeg,
    );

    if (result == null) return original;
    return File(result.path);
  }

  Future<void> _handleUpload() async {
    if (_selectedImage == null) return;

    setState(() {
      _isUploading = true;
      _errorMessage = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not signed in');

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final orgId = userDoc.data()?['orgId'];
      if (orgId == null) throw Exception('No organisation found.');

      // Step 1: upload image + create receipt doc. Photo is now safely
      // saved regardless of what happens next.
      final receiptId = await _receiptService.uploadReceipt(
        imageFile: _selectedImage!,
        orgId: orgId,
      );

      // Step 2: run OCR. Show scanning indicator while we wait.
      setState(() {
        _isUploading = false;
        _isScanning = true;
      });

      final parsed = await _runOcr(receiptId: receiptId, imageFile: _selectedImage!);

      if (!mounted) return;

      // Step 3: navigate to review screen with parsed data.
      // Use pushReplacement so the user can't go back to the upload screen
      // — the receipt is already saved at this point.
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ReceiptReviewScreen(
            receiptId: receiptId,
            parsed: parsed,
          ),
        ),
      );
    } catch (e) {
      setState(() {
        _errorMessage = 'Upload failed: $e';
        _isUploading = false;
        _isScanning = false;
      });
    }
  }

  /// Runs ML Kit on the image, saves raw extractedText to Firestore,
  /// then returns a ParsedReceipt for the review screen to display.
  /// If OCR fails for any reason, returns an empty ParsedReceipt so the
  /// user still reaches the review screen and can type fields manually.
  Future<ParsedReceipt> _runOcr({
    required String receiptId,
    required File imageFile,
  }) async {
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final inputImage = InputImage.fromFile(imageFile);
      final recognized = await textRecognizer.processImage(inputImage);
      final rawText = recognized.text;

      // Save raw text immediately so it's on the doc even if the user
      // backs out of the review screen without hitting Save.
      await _receiptService.updateExtractedText(
        receiptId: receiptId,
        extractedText: rawText,
      );

      return ReceiptParser.parse(rawText);
    } catch (e) {
      debugPrint('OCR failed for receipt $receiptId: $e');
      // Return an empty result — the review screen handles nulls gracefully.
      return ParsedReceipt(
        date: null,
        totalAmount: null,
        currency: null,
        lineItems: [],
      );
    } finally {
      await textRecognizer.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Upload Receipt')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: _selectedImage == null
                  ? Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.receipt_long,
                                size: 64, color: Colors.grey),
                            SizedBox(height: 8),
                            Text('No photo selected yet',
                                style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      ),
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        _selectedImage!,
                        width: double.infinity,
                        fit: BoxFit.contain,
                      ),
                    ),
            ),
            const SizedBox(height: 16),
            if (_errorMessage != null) ...[
              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 8),
            ],
            if (_isUploading || _isScanning)
              Column(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(
                    _isScanning ? 'Scanning receipt...' : 'Uploading...',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              )
            else if (_selectedImage == null)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickImage(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Camera'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickImage(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library),
                      label: const Text('Gallery'),
                    ),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() => _selectedImage = null),
                      child: const Text('Retake'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _handleUpload,
                      icon: const Icon(Icons.cloud_upload),
                      label: const Text('Upload'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}