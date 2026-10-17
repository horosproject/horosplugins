#import "DicomWriter.h"
#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>

static NSString *const kSecondaryCaptureSOPClass = @"1.2.840.10008.5.1.4.1.1.7";
static NSString *const kExplicitVRLittleEndian = @"1.2.840.10008.1.2.1";
static NSString *const kJPEGBaseline = @"1.2.840.10008.1.2.4.50";
static NSString *const kImplementationClassUID = @"2.25.261133428256468005143496634602431632860";
static NSString *const kImplementationVersion = @"JPG2DCM_HOROS";

#pragma mark - UIDs

// "2.25.<uuid as decimal>" (ISO/IEC 9834-8), no registered root needed.
static NSString *NewUID(void) {
    uuid_t bytes;
    [[NSUUID UUID] getUUIDBytes:bytes];
    uint8_t n[16];
    memcpy(n, bytes, 16);
    char digits[48];
    int len = 0;
    BOOL nonZero = YES;
    while (nonZero) {
        unsigned rem = 0;
        nonZero = NO;
        for (int i = 0; i < 16; i++) {
            unsigned cur = (rem << 8) | n[i];
            n[i] = (uint8_t)(cur / 10);
            rem = cur % 10;
            if (n[i]) nonZero = YES;
        }
        digits[len++] = (char)('0' + rem);
    }
    NSMutableString *s = [NSMutableString stringWithString:@"2.25."];
    for (int i = len - 1; i >= 0; i--) [s appendFormat:@"%c", digits[i]];
    return s;
}

#pragma mark - Element encoding (Explicit VR Little Endian)

static void PutU16(NSMutableData *d, uint16_t v) { uint16_t le = CFSwapInt16HostToLittle(v); [d appendBytes:&le length:2]; }
static void PutU32(NSMutableData *d, uint32_t v) { uint32_t le = CFSwapInt32HostToLittle(v); [d appendBytes:&le length:4]; }

static BOOL IsLongVR(NSString *vr) {
    return [@[@"OB", @"OW", @"OF", @"SQ", @"UT", @"UN"] containsObject:vr];
}

static void PutElement(NSMutableData *d, uint16_t group, uint16_t element, NSString *vr, NSData *value) {
    NSMutableData *v = [value mutableCopy] ?: [NSMutableData data];
    if (v.length % 2) {
        uint8_t pad = ([vr isEqualToString:@"UI"] || [vr isEqualToString:@"OB"]) ? 0x00 : 0x20;
        [v appendBytes:&pad length:1];
    }
    PutU16(d, group);
    PutU16(d, element);
    [d appendData:[vr dataUsingEncoding:NSASCIIStringEncoding]];
    if (IsLongVR(vr)) {
        PutU16(d, 0);
        PutU32(d, (uint32_t)v.length);
    } else {
        PutU16(d, (uint16_t)v.length);
    }
    [d appendData:v];
}

static void PutString(NSMutableData *d, uint16_t g, uint16_t e, NSString *vr, NSString *s) {
    PutElement(d, g, e, vr, [(s ?: @"") dataUsingEncoding:NSUTF8StringEncoding]);
}

static void PutUS(NSMutableData *d, uint16_t g, uint16_t e, uint16_t v) {
    NSMutableData *b = [NSMutableData data];
    PutU16(b, v);
    PutElement(d, g, e, @"US", b);
}

#pragma mark - Image loading

// Loads the image applying EXIF orientation and optional downscale.
static CGImageRef CreateOrientedImage(NSString *path, NSInteger maxDim, NSError **error) {
    CGImageSourceRef src = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], NULL);
    if (!src || CGImageSourceGetCount(src) == 0) {
        if (src) CFRelease(src);
        if (error) *error = [NSError errorWithDomain:@"JPEGToDICOM" code:1 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"No se pudo leer la imagen %@", path.lastPathComponent]}];
        return NULL;
    }
    NSDictionary *props = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(src, 0, NULL));
    NSInteger w = [props[(id)kCGImagePropertyPixelWidth] integerValue];
    NSInteger h = [props[(id)kCGImagePropertyPixelHeight] integerValue];
    NSInteger longest = MAX(w, h);
    NSInteger target = (maxDim > 0 && longest > maxDim) ? maxDim : longest;

    NSDictionary *opts = @{
        (id)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (id)kCGImageSourceCreateThumbnailWithTransform: @YES,
        (id)kCGImageSourceThumbnailMaxPixelSize: @(MAX(target, 1)),
        (id)kCGImageSourceShouldCacheImmediately: @YES,
    };
    CGImageRef img = CGImageSourceCreateThumbnailAtIndex(src, 0, (__bridge CFDictionaryRef)opts);
    CFRelease(src);
    if (!img && error) *error = [NSError errorWithDomain:@"JPEGToDICOM" code:2 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"No se pudo decodificar %@", path.lastPathComponent]}];
    return img;
}

// Renders into a packed 8-bit RGB buffer (white background for transparent PNGs).
static NSData *RGBPixels(CGImageRef img, size_t *outW, size_t *outH) {
    size_t w = CGImageGetWidth(img), h = CGImageGetHeight(img);
    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef ctx = CGBitmapContextCreate(NULL, w, h, 8, w * 4, cs, kCGImageAlphaNoneSkipLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(cs);
    if (!ctx) return nil;
    CGContextSetRGBFillColor(ctx, 1, 1, 1, 1);
    CGContextFillRect(ctx, CGRectMake(0, 0, w, h));
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), img);
    const uint8_t *rgba = CGBitmapContextGetData(ctx);
    NSMutableData *rgb = [NSMutableData dataWithLength:w * h * 3];
    uint8_t *o = rgb.mutableBytes;
    for (size_t i = 0; i < w * h; i++) {
        o[i * 3] = rgba[i * 4];
        o[i * 3 + 1] = rgba[i * 4 + 1];
        o[i * 3 + 2] = rgba[i * 4 + 2];
    }
    CGContextRelease(ctx);
    *outW = w;
    *outH = h;
    return rgb;
}

static NSData *BaselineJPEG(CGImageRef img, double quality) {
    // Re-render into an opaque sRGB bitmap so the encoder always gets 3-channel input.
    size_t w = 0, h = 0;
    NSData *rgb = RGBPixels(img, &w, &h);
    if (!rgb) return nil;
    CGDataProviderRef prov = CGDataProviderCreateWithCFData((__bridge CFDataRef)rgb);
    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGImageRef opaque = CGImageCreate(w, h, 8, 24, w * 3, cs, kCGImageAlphaNone | kCGBitmapByteOrderDefault, prov, NULL, false, kCGRenderingIntentDefault);
    CGColorSpaceRelease(cs);
    CGDataProviderRelease(prov);

    NSMutableData *out = [NSMutableData data];
    CGImageDestinationRef dst = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)out, CFSTR("public.jpeg"), 1, NULL);
    NSDictionary *opts = @{
        (id)kCGImageDestinationLossyCompressionQuality: @(quality),
        (id)kCGImagePropertyJFIFDictionary: @{(id)kCGImagePropertyJFIFIsProgressive: @NO},
    };
    CGImageDestinationAddImage(dst, opaque, (__bridge CFDictionaryRef)opts);
    BOOL ok = CGImageDestinationFinalize(dst);
    CFRelease(dst);
    CGImageRelease(opaque);
    return ok ? out : nil;
}

#pragma mark - DicomWriter

@implementation DicomWriter {
    NSString *_studyUID;
    NSString *_seriesUID;
    NSString *_date;
    NSString *_time;
    NSInteger _instanceNumber;
}

- (instancetype)init {
    if ((self = [super init])) {
        _studyUID = NewUID();
        _seriesUID = NewUID();
        NSDateFormatter *f = [NSDateFormatter new];
        f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        f.dateFormat = @"yyyyMMdd";
        _date = [f stringFromDate:[NSDate date]];
        f.dateFormat = @"HHmmss";
        _time = [f stringFromDate:[NSDate date]];
        _patientID = @"000001";
        _studyDescription = @"Fotos";
        _seriesDescription = @"Imagen a DICOM";
        _maxDimension = 1600;
        _compress = YES;
        _jpegQuality = 0.9;
    }
    return self;
}

- (NSString *)dicomPatientName {
    NSString *last = [self.patientLastName stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] ?: @"";
    NSString *first = [self.patientFirstName stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] ?: @"";
    return first.length ? [NSString stringWithFormat:@"%@^%@", last, first] : last;
}

- (NSData *)dicomDataForImageAtPath:(NSString *)path error:(NSError **)error {
    CGImageRef img = CreateOrientedImage(path, self.maxDimension, error);
    if (!img) return nil;

    size_t w = CGImageGetWidth(img), h = CGImageGetHeight(img);
    NSData *pixels;
    if (self.compress) {
        pixels = BaselineJPEG(img, self.jpegQuality);
    } else {
        pixels = RGBPixels(img, &w, &h);
    }
    CGImageRelease(img);
    if (!pixels) {
        if (error) *error = [NSError errorWithDomain:@"JPEGToDICOM" code:3 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"No se pudo procesar %@", path.lastPathComponent]}];
        return nil;
    }

    _instanceNumber++;
    NSString *sopUID = NewUID();
    NSString *ts = self.compress ? kJPEGBaseline : kExplicitVRLittleEndian;

    // File meta information (group 0002), always Explicit VR Little Endian.
    NSMutableData *meta = [NSMutableData data];
    uint8_t version[2] = {0x00, 0x01};
    PutElement(meta, 0x0002, 0x0001, @"OB", [NSData dataWithBytes:version length:2]);
    PutString(meta, 0x0002, 0x0002, @"UI", kSecondaryCaptureSOPClass);
    PutString(meta, 0x0002, 0x0003, @"UI", sopUID);
    PutString(meta, 0x0002, 0x0010, @"UI", ts);
    PutString(meta, 0x0002, 0x0012, @"UI", kImplementationClassUID);
    PutString(meta, 0x0002, 0x0013, @"SH", kImplementationVersion);

    NSMutableData *ds = [NSMutableData data];
    PutString(ds, 0x0008, 0x0005, @"CS", @"ISO_IR 192");
    PutString(ds, 0x0008, 0x0008, @"CS", @"DERIVED\\SECONDARY");
    PutString(ds, 0x0008, 0x0012, @"DA", _date);
    PutString(ds, 0x0008, 0x0013, @"TM", _time);
    PutString(ds, 0x0008, 0x0016, @"UI", kSecondaryCaptureSOPClass);
    PutString(ds, 0x0008, 0x0018, @"UI", sopUID);
    PutString(ds, 0x0008, 0x0020, @"DA", self.existingStudyUID ? self.existingStudyDate : _date);
    PutString(ds, 0x0008, 0x0021, @"DA", _date);
    PutString(ds, 0x0008, 0x0023, @"DA", _date);
    PutString(ds, 0x0008, 0x0030, @"TM", self.existingStudyUID ? self.existingStudyTime : _time);
    PutString(ds, 0x0008, 0x0031, @"TM", _time);
    PutString(ds, 0x0008, 0x0033, @"TM", _time);
    PutString(ds, 0x0008, 0x0050, @"SH", self.existingStudyUID ? self.existingAccessionNumber : @"");
    PutString(ds, 0x0008, 0x0060, @"CS", @"OT");
    PutString(ds, 0x0008, 0x0064, @"CS", @"WSD");
    PutString(ds, 0x0008, 0x0090, @"PN", @"");
    PutString(ds, 0x0008, 0x1030, @"LO", self.studyDescription);
    PutString(ds, 0x0008, 0x103E, @"LO", self.seriesDescription);
    PutString(ds, 0x0010, 0x0010, @"PN", [self dicomPatientName]);
    PutString(ds, 0x0010, 0x0020, @"LO", self.patientID);
    PutString(ds, 0x0010, 0x0030, @"DA", self.patientBirthDate);
    PutString(ds, 0x0010, 0x0040, @"CS", self.patientSex);
    PutString(ds, 0x0020, 0x000D, @"UI", self.existingStudyUID ?: _studyUID);
    PutString(ds, 0x0020, 0x000E, @"UI", _seriesUID);
    PutString(ds, 0x0020, 0x0010, @"SH", self.existingStudyUID ? self.existingStudyID : @"1");
    // High series number so it never collides with the existing series of the study.
    PutString(ds, 0x0020, 0x0011, @"IS", self.existingStudyUID ? @"9001" : @"1");
    PutString(ds, 0x0020, 0x0013, @"IS", [NSString stringWithFormat:@"%ld", (long)_instanceNumber]);
    PutString(ds, 0x0020, 0x0020, @"CS", @"");
    PutUS(ds, 0x0028, 0x0002, 3);
    PutString(ds, 0x0028, 0x0004, @"CS", self.compress ? @"YBR_FULL_422" : @"RGB");
    PutUS(ds, 0x0028, 0x0006, 0);
    PutUS(ds, 0x0028, 0x0010, (uint16_t)h);
    PutUS(ds, 0x0028, 0x0011, (uint16_t)w);
    PutUS(ds, 0x0028, 0x0100, 8);
    PutUS(ds, 0x0028, 0x0101, 8);
    PutUS(ds, 0x0028, 0x0102, 7);
    PutUS(ds, 0x0028, 0x0103, 0);

    if (self.compress) {
        PutString(ds, 0x0028, 0x2110, @"CS", @"01");
        PutString(ds, 0x0028, 0x2114, @"CS", @"ISO_10918_1");
        // Encapsulated Pixel Data: undefined length, empty offset table, one fragment.
        PutU16(ds, 0x7FE0); PutU16(ds, 0x0010);
        [ds appendData:[@"OB" dataUsingEncoding:NSASCIIStringEncoding]];
        PutU16(ds, 0); PutU32(ds, 0xFFFFFFFF);
        PutU16(ds, 0xFFFE); PutU16(ds, 0xE000); PutU32(ds, 0);
        NSMutableData *frag = [pixels mutableCopy];
        if (frag.length % 2) { uint8_t z = 0; [frag appendBytes:&z length:1]; }
        PutU16(ds, 0xFFFE); PutU16(ds, 0xE000); PutU32(ds, (uint32_t)frag.length);
        [ds appendData:frag];
        PutU16(ds, 0xFFFE); PutU16(ds, 0xE0DD); PutU32(ds, 0);
    } else {
        PutElement(ds, 0x7FE0, 0x0010, @"OB", pixels);
    }

    NSMutableData *file = [NSMutableData dataWithLength:128];
    [file appendData:[@"DICM" dataUsingEncoding:NSASCIIStringEncoding]];
    NSMutableData *groupLength = [NSMutableData data];
    PutU32(groupLength, (uint32_t)meta.length);
    PutElement(file, 0x0002, 0x0000, @"UL", groupLength);
    [file appendData:meta];
    [file appendData:ds];
    return file;
}

@end
