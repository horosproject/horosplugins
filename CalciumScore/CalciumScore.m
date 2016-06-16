//
//  CalciumScore.m
//

#import "CalciumScore.h"
#import <HorosAPI/ROI.h>

@implementation CalciumScore

- (long) filterImage:(NSString*) menuName
{
	// The entire source code of this plugin is IN OsiriX main source code...
	
	[viewerController calciumScoring: self];
	
	return 0;
}
@end
