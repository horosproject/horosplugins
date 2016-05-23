//
//   DCMJpegImportFilter
//  
//

#import <Foundation/Foundation.h>
#import <HorosAPI/PluginFilter.h>

@class DCMCalendarDate, DICOMExport;

@interface DCMJpegImportFilter : PluginFilter
{
	int imageNumber;
	DICOMExport *e;
    IBOutlet NSView *accessoryView;
    BOOL selectedStudyAvailable;
}

@property BOOL selectedStudyAvailable;

- (long) filterImage:(NSString*) menuName;
- (NSString*) convertImageToDICOM:(NSString *)path source:(NSString *)src;

@end
