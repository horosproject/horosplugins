#import <Foundation/Foundation.h>

// Reads patient/study string attributes (groups 0008-0020) from a DICOM file.
// Keys are 8-hex-digit tags, e.g. @"00100010" for PatientName.
// Supports Explicit and Implicit VR Little Endian (the usual transfer syntaxes,
// including compressed pixel data, which is never reached). Returns nil otherwise.
NSDictionary<NSString *, NSString *> *ReadDicomHeader(NSString *path);
