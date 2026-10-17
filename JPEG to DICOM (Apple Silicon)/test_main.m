// Command-line harness to test DicomWriter outside Horos:
//   ./jpg2dcm_test <image> <out.dcm> <Apellido> <Nombre> [raw]
#import <Foundation/Foundation.h>
#import "DicomWriter.h"
#import "DicomHeaderReader.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        // ./jpg2dcm_test --header file.dcm  → which patient/study tags were found (values masked)
        if (argc == 3 && strcmp(argv[1], "--header") == 0) {
            NSDictionary *h = ReadDicomHeader(@(argv[2]));
            if (!h) { printf("no se pudo leer\n"); return 1; }
            for (NSString *k in @[@"00080005", @"00100010", @"00100020", @"00100030", @"00100040", @"0020000D", @"00080020", @"00080030", @"00200010", @"00080050", @"00081030"]) {
                NSString *v = h[k];
                printf("%s: %s\n", k.UTF8String, v ? [NSString stringWithFormat:@"%lu chars%s", (unsigned long)v.length, [v containsString:@"^"] ? " (con ^)" : ""].UTF8String : "-");
            }
            return 0;
        }
        if (argc < 5) {
            fprintf(stderr, "uso: %s imagen salida.dcm Apellido Nombre [raw]\n", argv[0]);
            return 2;
        }
        DicomWriter *w = [DicomWriter new];
        w.patientLastName = @(argv[3]);
        w.patientFirstName = @(argv[4]);
        if (argc > 5 && strcmp(argv[5], "raw") == 0) {
            w.compress = NO;
            w.maxDimension = 0;
        }
        NSError *err = nil;
        NSData *d = [w dicomDataForImageAtPath:@(argv[1]) error:&err];
        if (!d) {
            fprintf(stderr, "error: %s\n", err.localizedDescription.UTF8String);
            return 1;
        }
        [d writeToFile:@(argv[2]) atomically:YES];
        printf("OK %lu bytes\n", (unsigned long)d.length);
    }
    return 0;
}
