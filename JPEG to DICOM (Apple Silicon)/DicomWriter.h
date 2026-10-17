#import <Foundation/Foundation.h>

// Converts images (JPG/PNG/HEIC/...) to DICOM Secondary Capture files.
// All images given to one writer share the same Study and Series.
@interface DicomWriter : NSObject

@property (copy) NSString *patientLastName;
@property (copy) NSString *patientFirstName;
@property (copy) NSString *patientID;
@property (copy) NSString *studyDescription;
@property (copy) NSString *seriesDescription;
// Optional: DICOM DA (yyyyMMdd) and CS (M/F/O).
@property (copy) NSString *patientBirthDate;
@property (copy) NSString *patientSex;

// Set to add the images as a new series of an existing study.
// The other study attributes are copied as-is so Horos keeps them grouped.
@property (copy) NSString *existingStudyUID;
@property (copy) NSString *existingStudyDate;
@property (copy) NSString *existingStudyTime;
@property (copy) NSString *existingStudyID;
@property (copy) NSString *existingAccessionNumber;
// 0 = keep original size.
@property NSInteger maxDimension;
// YES = JPEG Baseline inside the DICOM (small files); NO = uncompressed RGB.
@property BOOL compress;
// 0.0 - 1.0, only used when compress == YES.
@property double jpegQuality;

- (instancetype)init;

// Returns the DICOM bytes for the image at `path`, or nil and sets `error`.
- (NSData *)dicomDataForImageAtPath:(NSString *)path error:(NSError **)error;

@end
