#import "DicomHeaderReader.h"

typedef struct {
    const uint8_t *bytes;
    NSUInteger length;
    NSUInteger pos;
    BOOL explicitVR;
} Cursor;

static BOOL Has(Cursor *c, NSUInteger n) { return c->pos + n <= c->length; }
static uint16_t U16(Cursor *c) { uint16_t v = (uint16_t)(c->bytes[c->pos] | (c->bytes[c->pos + 1] << 8)); c->pos += 2; return v; }
static uint32_t U32(Cursor *c) { uint32_t v = (uint32_t)c->bytes[c->pos] | ((uint32_t)c->bytes[c->pos + 1] << 8) | ((uint32_t)c->bytes[c->pos + 2] << 16) | ((uint32_t)c->bytes[c->pos + 3] << 24); c->pos += 4; return v; }

static BOOL IsLongVR(const char vr[2]) {
    static const char *longVRs[] = {"OB", "OW", "OF", "OD", "OL", "OV", "SQ", "UT", "UN", "UC", "UR"};
    for (size_t i = 0; i < sizeof(longVRs) / sizeof(*longVRs); i++)
        if (vr[0] == longVRs[i][0] && vr[1] == longVRs[i][1]) return YES;
    return NO;
}

// Reads one element header. Returns NO at end of data.
static BOOL ReadHeader(Cursor *c, uint16_t *group, uint16_t *element, char vr[2], uint32_t *len) {
    if (!Has(c, 8)) return NO;
    *group = U16(c);
    *element = U16(c);
    // Item / delimitation tags never carry a VR.
    if (*group == 0xFFFE) { vr[0] = vr[1] = 0; *len = U32(c); return YES; }
    if (c->explicitVR) {
        vr[0] = (char)c->bytes[c->pos];
        vr[1] = (char)c->bytes[c->pos + 1];
        c->pos += 2;
        if (IsLongVR(vr)) {
            if (!Has(c, 6)) return NO;
            c->pos += 2;
            *len = U32(c);
        } else {
            *len = U16(c);
        }
    } else {
        vr[0] = vr[1] = 0;
        *len = U32(c);
    }
    return YES;
}

static BOOL SkipUndefined(Cursor *c);

// Skips the elements of one undefined-length item, up to its delimiter.
static BOOL SkipItemBody(Cursor *c) {
    uint16_t g, e; char vr[2]; uint32_t len;
    while (ReadHeader(c, &g, &e, vr, &len)) {
        if (g == 0xFFFE && e == 0xE00D) return YES;
        if (len == 0xFFFFFFFF) { if (!SkipUndefined(c)) return NO; continue; }
        if (!Has(c, len)) return NO;
        c->pos += len;
    }
    return NO;
}

// Skips an undefined-length sequence (or encapsulated data) up to its delimiter.
static BOOL SkipUndefined(Cursor *c) {
    uint16_t g, e; char vr[2]; uint32_t len;
    while (ReadHeader(c, &g, &e, vr, &len)) {
        if (g == 0xFFFE && e == 0xE0DD) return YES;
        if (g != 0xFFFE || e != 0xE000) return NO;
        if (len == 0xFFFFFFFF) { if (!SkipItemBody(c)) return NO; continue; }
        if (!Has(c, len)) return NO;
        c->pos += len;
    }
    return NO;
}

static NSString *Decode(const uint8_t *b, uint32_t len, BOOL utf8) {
    NSData *d = [NSData dataWithBytes:b length:len];
    NSString *s = utf8 ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : nil;
    if (!s) s = [[NSString alloc] initWithData:d encoding:NSISOLatin1StringEncoding];
    return [s stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" \0"]];
}

NSDictionary<NSString *, NSString *> *ReadDicomHeader(NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
    if (data.length < 132 || memcmp((const uint8_t *)data.bytes + 128, "DICM", 4) != 0) return nil;

    Cursor c = {data.bytes, data.length, 132, YES};
    NSString *ts = nil;
    // File meta group: always explicit VR little endian.
    while (Has(&c, 8)) {
        NSUInteger start = c.pos;
        uint16_t g, e; char vr[2]; uint32_t len;
        if (!ReadHeader(&c, &g, &e, vr, &len)) return nil;
        if (g != 0x0002) { c.pos = start; break; }
        if (!Has(&c, len)) return nil;
        if (e == 0x0010) ts = Decode(c.bytes + c.pos, len, NO);
        c.pos += len;
    }
    if ([ts isEqualToString:@"1.2.840.10008.1.2"]) c.explicitVR = NO;
    else if ([ts isEqualToString:@"1.2.840.10008.1.2.2"] || [ts isEqualToString:@"1.2.840.10008.1.2.1.99"]) return nil;

    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    BOOL utf8 = NO;
    uint16_t g, e; char vr[2]; uint32_t len;
    while (ReadHeader(&c, &g, &e, vr, &len)) {
        if (g > 0x0020) break;
        if (len == 0xFFFFFFFF) { if (!SkipUndefined(&c)) break; continue; }
        if (!Has(&c, len)) break;
        BOOL isSequence = c.explicitVR ? (vr[0] == 'S' && vr[1] == 'Q') : NO;
        if (!isSequence && len < 1024) {
            NSString *key = [NSString stringWithFormat:@"%04X%04X", g, e];
            if (g == 0x0008 && e == 0x0005) {
                NSString *cs = Decode(c.bytes + c.pos, len, NO);
                utf8 = [cs containsString:@"192"];
            }
            out[key] = Decode(c.bytes + c.pos, len, utf8);
        }
        c.pos += len;
    }
    return out;
}
