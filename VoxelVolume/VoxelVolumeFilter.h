//
//  VoxelVolumeFilter.h
//  VoxelVolume
//
//  Copyright (c) 2016 soren. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <OsiriXAPI/PluginFilter.h>

@interface VoxelVolumeFilter : PluginFilter {

}

- (long) filterImage:(NSString*) menuName;
- (float) calcZpos:(float*)IOP :(float*)IPP;

@end
