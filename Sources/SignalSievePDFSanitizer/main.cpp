// SPDX-License-Identifier: MPL-2.0
#include <qpdf/QPDF.hh>
#include <qpdf/QPDFObjectHandle.hh>
#include <qpdf/QPDFWriter.hh>

#include <iostream>

namespace {

QPDFObjectHandle dictionaryFor(QPDFObjectHandle object)
{
    if (object.isDictionary()) {
        return object;
    }
    if (object.isStream()) {
        return object.getDict();
    }
    return QPDFObjectHandle::newNull();
}

bool isAppliedSignature(QPDFObjectHandle dictionary)
{
    if (!dictionary.isDictionary()) {
        return false;
    }
    auto type = dictionary.getKey("/Type");
    bool signatureType = type.isNameAndEquals("/Sig") ||
        type.isNameAndEquals("/DocTimeStamp");
    bool hasPayload = dictionary.hasKey("/ByteRange") ||
        dictionary.hasKey("/Contents");
    return signatureType && hasPayload;
}

} // namespace

int main(int argc, char* argv[])
{
    if (argc != 3) {
        std::cerr << "usage: SignalSievePDFSanitizer input.pdf output.pdf\n";
        return 64;
    }
    try {
        QPDF pdf;
        pdf.setSuppressWarnings(true);
        pdf.processFile(argv[1]);
        if (pdf.anyWarnings()) {
            std::cerr << "input PDF required parser recovery\n";
            return 12;
        }
        if (pdf.isEncrypted()) {
            std::cerr << "encrypted PDF refused\n";
            return 11;
        }

        auto root = pdf.getRoot();
        if (root.hasKey("/Perms")) {
            std::cerr << "signed or certified PDF refused\n";
            return 10;
        }
        auto objects = pdf.getAllObjects();
        for (auto object : objects) {
            if (isAppliedSignature(dictionaryFor(object))) {
                std::cerr << "signed PDF refused\n";
                return 10;
            }
        }

        // Info, XMP Metadata, and application PieceInfo are non-rendering
        // metadata surfaces. Removing their references lets qpdf omit the
        // now-unreachable objects while preserving pages, forms, and links.
        pdf.getTrailer().removeKey("/Info");
        for (auto object : objects) {
            auto dictionary = dictionaryFor(object);
            if (!dictionary.isDictionary()) {
                continue;
            }
            if (dictionary.hasKey("/Metadata")) {
                dictionary.removeKey("/Metadata");
            }
            if (dictionary.hasKey("/PieceInfo")) {
                dictionary.removeKey("/PieceInfo");
                dictionary.removeKey("/LastModified");
            }
        }

        QPDFWriter writer(pdf, argv[2]);
        writer.setStaticID(true);
        writer.setPreserveUnreferencedObjects(false);
        writer.write();
        std::cout << "{\"schemaVersion\":1,\"sanitized\":true}\n";
        return 0;
    } catch (std::exception const& error) {
        std::cerr << error.what() << "\n";
        return 12;
    }
}
