//
//  VoxelVolumeFilter.m
//  VoxelVolume
//
//  Copyright (c) 2016 soren. All rights reserved.
//

#import "VoxelVolumeFilter.h"
#import <OsiriXAPI/DICOMExport.h>
#import "OsiriXAPI/browserController.h"
#import "OsiriXAPI/DicomDatabase.h"

@implementation VoxelVolumeFilter

- (float) calcZpos:(float*)IOP :(float*)IPP
{
    float xpos=IPP[0];
    float ypos=IPP[1];
    float zpos=IPP[2];
    
    float dst_nrm_IOP_x = IOP[2-1] * IOP[6-1] - IOP[3-1] * IOP[5-1];
    float dst_nrm_IOP_y = IOP[3-1] * IOP[4-1] - IOP[1-1] * IOP[6-1];
    float dst_nrm_IOP_z = IOP[1-1] * IOP[5-1] - IOP[2-1] * IOP[4-1];
    
    float newz = dst_nrm_IOP_x * xpos + dst_nrm_IOP_y * ypos+ dst_nrm_IOP_z * zpos;
    
    return newz;
    
    /*
     IOP=imageorient;
     
     
     xpos=imagepos(1);
     ypos=imagepos(2);
     zpos=imagepos(3);
     
     %* "C.7.6.2.1.1 Image Position And Image Orientation. The Image Position (0020,0032) specifies the x, y,
     %and z coordinates of the upper left hand corner of the image; it is the center of the first voxel transmitted.
     %Image Orientation (0020,0037) specifies the direction cosines of the first row and the first column with respect to the patient.
     %These Attributes shall be provide as a pair. Row value for the x, y, and z axes respectively followed by the Column value for the x,
     %y, and z axes respectively. The direction of the axes is defined fully by the patient's orientation. The x-axis is increasing to the
     %left hand side of the patient. The y-axis is increasing to the posterior side of the patient.
     %The z-axis is increasing toward the head of the patient. The patient based coordinate system is a right handed system,%
     %i.e. the vector cross product of a unit vector along the positive x-axis and a unit vector along the positive y-axis is equal to a unit vector%
     %along the positive z-axis."
     
     dst_nrm_dircos_x = dircos(2) * dircos(6) - dircos(3) * dircos(5);
     dst_nrm_dircos_y = dircos(3) * dircos(4) - dircos(1) * dircos(6);
     dst_nrm_dircos_z = dircos(1) * dircos(5) - dircos(2) * dircos(4);
     
     %newx = dircos(1) * xpos + dircos(2)* ypos + dircos(3) * zpos;
     
     %newy = dircos(4)* xpos + dircos(5)* ypos + dircos(6) * zpos;
     
     newz = dst_nrm_dircos_x * xpos + dst_nrm_dircos_y * ypos+ dst_nrm_dircos_z * zpos;
     
     
     %newx=(newx*1e3+.5);
     %newy=(newy*1e3+.5);
     %newz=(newz*1e3+.5);
     */
}

- (void) initPlugin
{
}

- (long) filterImage:(NSString*) menuName
{
    ViewerController	*new2DViewer;
    NSMutableArray  *roiSeriesList;
    NSMutableArray  *roiImageList;
    //ROI				*mROI;
    DCMPix			*curImg;
    float           *floatptr;
    // In this plugin, we will simply duplicate the current 2D window!
    
    
    
    new2DViewer = [self duplicateCurrent2DViewerWindow];
    if(! new2DViewer) return -1; // Errors
    
    
    float ww=[viewerController curWW];
    float wl=[viewerController curWL];
    
    
    [new2DViewer setWL:0.5 WW:1];
    
    [new2DViewer needsDisplayUpdate];
    
    
    roiSeriesList = [viewerController roiList];
    
    
    //loop slices
    int nslices=[viewerController getNumberOfImages];
    DICOMExport* dicomExport = [[DICOMExport alloc] init];
    
    //    float projected_z[nslices];
    
    int voxelcount=0;
    
    
    //prep a short int buffer
    curImg=[[new2DViewer pixList] objectAtIndex: 0];
    
    long nrows=[curImg pheight];
    long ncols=[curImg pwidth];
    //  unsigned short int myimg[[curImg pwidth]*[curImg pheight]];
    
    NSMutableData* data = [NSMutableData dataWithLength:sizeof(unsigned short int) *nrows*ncols*nslices];
    unsigned short int* myimg = [data mutableBytes];
    
    unsigned int myimg_offset;
    
    NSMutableArray *zpos_voxelcount_dict=[NSMutableArray array];
    
    
    //dictionary of unique name along with incremental index
    NSMutableDictionary *name_indx_dict=[NSMutableDictionary dictionary];
    int myindex=0;
    for (int k=0;k<nslices;k++)
    {
        
        myimg_offset=nrows*ncols*k;
        roiImageList=[roiSeriesList objectAtIndex:k];
        
        curImg=[[new2DViewer pixList] objectAtIndex: k];
        
        floatptr=[curImg fImage];
        //        unsigned short int myimg[[curImg pwidth]*[curImg pheight]];
        
        
        for (int ipix=0;ipix<([curImg pwidth]*[curImg pheight]); ipix++)
        {
            myimg[ipix+myimg_offset]=0;
            floatptr[ipix]=0;   //we need a clean bg now in the copy of the original
        }
        
        int fillvalue=-1;
        for (int iroi=0;iroi<roiImageList.count;iroi++) //will rasterize each roi in this slice and put 1's where the ROI was
        {
       //    [[roiImageList objectAtIndex:iroi] ]
        
            NSString* nameString=[[roiImageList objectAtIndex:iroi] name];
            
            //is this name is not already seen
            //then increment the index and add key with index
            
            if ([name_indx_dict objectForKey:nameString]==nil)
            {
                myindex++;
                [name_indx_dict setObject:[NSNumber numberWithInt:myindex] forKey:nameString];
                fillvalue=myindex;
            } else  //if it is, get the index
            {
                
                fillvalue=[[name_indx_dict objectForKey:nameString] intValue];
            }
            
            
            
            
            [curImg fillROI:[roiImageList objectAtIndex:iroi] :fillvalue: -99999:99999 :NO];
              NSLog(@"name is: %@", nameString);
          
            
            // change the above to give a new value to each unseen name store in dict
         
        }
        
        
        //change below to calculate volumes for each discrete label in stead and store in a dict
        //THIS CAN WAIT BECAUSE THE ABOVE IS MORE IMMEDITATE
        int slicecount=0;
        for (int ipix=0;ipix<([curImg pwidth]*[curImg pheight]); ipix++)
        {
            if (floatptr[ipix]>0.5)
            {
                myimg[ipix+myimg_offset]=1;
                voxelcount++;
                slicecount++;
            }
        }
        
        
        float orientation[9];
        float origin[3];
        [curImg orientation:&orientation[0]];
        [curImg origin:&origin[0]];
        
        float cZ=[self calcZpos :&orientation[0] :&origin[0] ];
        //  NSNumber *num = [NSNumber numberWithFloat:cZ];
        //  [projected_z addObject:(num)];
        
        
        [zpos_voxelcount_dict addObject:@{ @"Zpos": [NSNumber numberWithFloat:cZ] ,
                                           @"voxelcount": [NSNumber numberWithInt:(slicecount)]}];
        
        
        
    } //*end of rasterization and capture of voxel count and projected z location
    
    
    NSArray *sorted = [zpos_voxelcount_dict sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"Zpos" ascending:YES]]];
    
    
    //calculate volume
    bool equidistant=true;
    
    float prepos=[[sorted[0] objectForKey:(@"Zpos")] floatValue];
    
    float totalvolume=0;
    
    double dx=[curImg pixelSpacingX];
    double dy=[curImg pixelSpacingY];
    float delta;
    float deltaold;
    for (int k=1;k<nslices;k++)
    {
        float ccount=[[sorted[k-1] objectForKey:(@"voxelcount")] floatValue];
        float cpos=[[sorted[k] objectForKey:(@"Zpos")] floatValue];
        
        delta=cpos-prepos;
        
        if ( (k>1) && (fabs(delta-deltaold)>0.01) )
            equidistant=false;
        
        float cvolume=delta*dx*dy * ccount/1000.0;
        
        totalvolume+=cvolume;
        prepos=cpos;
        deltaold=delta;
    }
    
    //last slice:
    float ccount= [  [ [sorted lastObject] objectForKey:(@"voxelcount")] floatValue];
    float cvolume=delta*dx*dy * ccount/1000.0;    //now de
    totalvolume+=cvolume;
    
    
    
    
    
    NSString *volume_str=[NSString stringWithFormat:@"ROImask:%2.2f mL",totalvolume];
    
    for (int k=0;k<nslices;k++)
    {
        
        myimg_offset=nrows*ncols*k;
        
        
        curImg=[[new2DViewer pixList] objectAtIndex: k];
        
        
        
        //*now iterate slices again to clone DICOMs
        //*convert to an int16 buffer..
        
        //*now write this DICOM to file...
        [dicomExport setSourceFile: [curImg srcFile]];
        [dicomExport setSeriesDescription: volume_str];
        //*force same seriesUID...
        [dicomExport setSeriesNumber: 35466];
        
        [dicomExport setPixelData:(unsigned char *)&myimg[myimg_offset] samplesPerPixel:1 bitsPerSample:16 width:[curImg pwidth] height:[curImg pheight]];
        [dicomExport setSigned:(true)];
        [dicomExport setOffset:(0)];
        [dicomExport setPixelSpacing:[curImg pixelSpacingX] :[curImg pixelSpacingY]];
        float orientation[9];
        float origin[3];
        [curImg orientation:&orientation[0]];
        [curImg origin:&origin[0]];
        [dicomExport setPosition:&origin[0]];
        [dicomExport setOrientation:&orientation[0]];
        // [dicomExport setValue:<#(id)#> forKey:<#(NSString *)#>    ];
        //[dicomExport W]
        //([curImg pixelSpacingX] :[curImg pixelSpacingY]);
        //[dicomExport
        
        // NSString *dcmname=[@(k) stringValue];
        //NSString* f = [dicomExport writeDCMFile: [@"/Users/CRISP/Desktop/p" stringByAppendingString:dcmname]];
        NSString *createdFile = [[dicomExport writeDCMFile: nil] retain];
        if( createdFile)
            [BrowserController.currentBrowser.database addFilesAtPaths: [NSArray arrayWithObject: createdFile]
                                                     postNotifications: YES
                                                             dicomOnly: YES
                                                   rereadExistingItems: YES
                                                     generatedByOsiriX: YES];
        [createdFile autorelease];
        
    }
    
    
    [viewerController setWL:wl WW:ww];
    
    
    NSAlert *alert=[[[NSAlert alloc] init] autorelease];
    //double interval=[curImg sliceInterval];
    
    NSString *countstr=[NSString stringWithFormat:@"Voxelcount is %d Volume is %2.2f and equidistance flag is %1u",voxelcount,totalvolume,equidistant];
    [alert setMessageText: countstr];
    [alert runModal];
    
    //[viewerController set
    
    
    
    return 0;
    
    
}

@end
