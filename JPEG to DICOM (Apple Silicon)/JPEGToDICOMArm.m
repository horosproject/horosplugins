#import <Cocoa/Cocoa.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "PluginFilter.h"
#import "DicomWriter.h"
#import "DicomHeaderReader.h"

#pragma clang diagnostic ignored "-Warc-performSelector-leaks"

#pragma mark - Selected patient

// Patient and study data of the study selected in the Horos browser.
@interface JTDSelectedStudy : NSObject
@property (copy) NSString *lastName, *firstName, *patientID, *birthDate, *sex;
@property (copy) NSString *studyUID, *studyDate, *studyTime, *studyID, *accession, *studyDescription;
@property (readonly) NSString *displayName;
@end

@implementation JTDSelectedStudy
- (NSString *)displayName {
    return self.firstName.length ? [NSString stringWithFormat:@"%@ %@", self.lastName, self.firstName] : self.lastName;
}
@end

static NSString *DA(NSDate *d) {
    if (![d isKindOfClass:NSDate.class]) return @"";
    NSDateFormatter *f = [NSDateFormatter new];
    f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    f.dateFormat = @"yyyyMMdd";
    return [f stringFromDate:d];
}

static NSString *Str(id v) { return [v isKindOfClass:NSString.class] ? v : @""; }

static id StudyForObject(NSManagedObject *o) {
    NSString *entity = o.entity.name;
    if ([entity isEqualToString:@"Study"]) return o;
    if ([entity isEqualToString:@"Series"]) return [o valueForKey:@"study"];
    if ([entity isEqualToString:@"Image"]) return [o valueForKeyPath:@"series.study"];
    return nil;
}

// Header of any image of the study, read straight from its DICOM file.
static NSDictionary *HeaderForStudy(NSManagedObject *study) {
    for (NSManagedObject *series in [study valueForKey:@"series"]) {
        for (NSManagedObject *image in [series valueForKey:@"images"]) {
            NSString *path = [image respondsToSelector:@selector(completePath)] ? [image performSelector:@selector(completePath)] : nil;
            NSDictionary *h = path ? ReadDicomHeader(path) : nil;
            if ([h[@"00100010"] length] && [h[@"0020000D"] length]) return h;
            break;  // one try per series is enough
        }
    }
    return nil;
}

static JTDSelectedStudy *SelectedStudy(void) {
    Class bc = NSClassFromString(@"BrowserController");
    id browser = [bc respondsToSelector:@selector(currentBrowser)] ? [bc performSelector:@selector(currentBrowser)] : nil;
    NSArray *selection = [browser respondsToSelector:@selector(databaseSelection)] ? [browser performSelector:@selector(databaseSelection)] : nil;
    NSManagedObject *study = nil;
    for (id o in selection) {
        if ([o isKindOfClass:NSManagedObject.class] && (study = StudyForObject(o))) break;
    }
    if (!study) return nil;

    JTDSelectedStudy *s = [JTDSelectedStudy new];
    NSDictionary *h = HeaderForStudy(study);
    if (h) {
        // PN: Apellido^Nombre^Segundo^Prefijo^Sufijo
        NSArray *pn = [h[@"00100010"] componentsSeparatedByString:@"^"];
        s.lastName = pn[0];
        s.firstName = pn.count > 1 ? [[[pn subarrayWithRange:NSMakeRange(1, MIN(pn.count - 1, 2))] componentsJoinedByString:@" "] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] : @"";
        s.patientID = h[@"00100020"] ?: @"";
        s.birthDate = h[@"00100030"] ?: @"";
        s.sex = h[@"00100040"] ?: @"";
        s.studyUID = h[@"0020000D"];
        s.studyDate = h[@"00080020"] ?: @"";
        s.studyTime = h[@"00080030"] ?: @"";
        s.studyID = h[@"00200010"] ?: @"";
        s.accession = h[@"00080050"] ?: @"";
        s.studyDescription = h[@"00081030"] ?: @"";
    } else {
        // Fallback to the database. Horos stores the name with spaces instead of '^', so we
        // can't tell surname from given name: keep it whole so it matches the existing patient.
        s.lastName = Str([study valueForKey:@"name"]);
        s.firstName = @"";
        s.patientID = Str([study valueForKey:@"patientID"]);
        s.birthDate = DA([study valueForKey:@"dateOfBirth"]);
        s.sex = Str([study valueForKey:@"patientSex"]);
        s.studyUID = Str([study valueForKey:@"studyInstanceUID"]);
        NSDate *date = [study valueForKey:@"date"];
        s.studyDate = DA(date);
        if ([date isKindOfClass:NSDate.class]) {
            NSDateFormatter *f = [NSDateFormatter new];
            f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
            f.dateFormat = @"HHmmss";
            s.studyTime = [f stringFromDate:date];
        } else {
            s.studyTime = @"";
        }
        s.studyID = Str([study valueForKey:@"id"]);
        s.accession = Str([study valueForKey:@"accessionNumber"]);
        s.studyDescription = Str([study valueForKey:@"studyName"]);
    }
    return s.lastName.length ? s : nil;
}

#pragma mark - Form

@interface JTDForm : NSObject
@property NSTextField *last, *first, *pid, *study;
@property NSButton *useSelected, *addToStudy, *compress, *saveCopy;
@property JTDSelectedStudy *selected;
@property (copy) NSString *typedLast, *typedFirst, *typedPID, *typedStudy;
@end

@implementation JTDForm

- (void)useSelectedChanged:(id)sender {
    BOOL on = self.useSelected.state == NSControlStateValueOn;
    if (on) {
        self.typedLast = self.last.stringValue;
        self.typedFirst = self.first.stringValue;
        self.typedPID = self.pid.stringValue;
        self.last.stringValue = self.selected.lastName;
        self.first.stringValue = self.selected.firstName;
        self.pid.stringValue = self.selected.patientID;
    } else {
        self.last.stringValue = self.typedLast ?: @"";
        self.first.stringValue = self.typedFirst ?: @"";
        self.pid.stringValue = self.typedPID ?: @"000001";
        self.addToStudy.state = NSControlStateValueOff;
        [self addToStudyChanged:nil];
    }
    self.last.enabled = self.first.enabled = self.pid.enabled = !on;
    self.addToStudy.enabled = on;
}

- (void)addToStudyChanged:(id)sender {
    BOOL on = self.addToStudy.state == NSControlStateValueOn;
    if (on) {
        self.typedStudy = self.study.stringValue;
        self.study.stringValue = self.selected.studyDescription.length ? self.selected.studyDescription : @"(sin descripción)";
    } else if (!self.study.enabled) {
        self.study.stringValue = self.typedStudy ?: @"Fotos";
    }
    self.study.enabled = !on;
}

@end

@interface JPEGToDICOMArm : PluginFilter
@end

@implementation JPEGToDICOMArm

- (void)initPlugin {
}

#pragma mark - UI helpers

static NSTextField *Label(NSString *s) {
    NSTextField *l = [NSTextField labelWithString:s];
    l.alignment = NSTextAlignmentRight;
    return l;
}

static NSTextField *Field(NSString *value, NSString *placeholder) {
    NSTextField *f = [NSTextField textFieldWithString:value ?: @""];
    f.placeholderString = placeholder;
    [f.widthAnchor constraintEqualToConstant:260].active = YES;
    return f;
}

- (NSArray<NSURL *> *)chooseImages {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.title = @"Elegí las imágenes a convertir";
    panel.prompt = @"Elegir";
    panel.allowsMultipleSelection = YES;
    panel.canChooseDirectories = NO;
    panel.allowedContentTypes = @[UTTypeImage];
    panel.directoryURL = [NSFileManager.defaultManager URLsForDirectory:NSDownloadsDirectory inDomains:NSUserDomainMask].firstObject;
    return [panel runModal] == NSModalResponseOK ? panel.URLs : nil;
}

// Returns a configured writer, or nil if the user cancelled.
- (DicomWriter *)askPatientForCount:(NSUInteger)count selected:(JTDSelectedStudy *)selected saveCopy:(BOOL *)saveCopy {
    JTDForm *form = [JTDForm new];
    form.selected = selected;
    form.last = Field(@"", @"Apellido");
    form.first = Field(@"", @"Nombre");
    form.pid = Field(@"000001", @"ID de paciente");
    form.study = Field(@"Fotos", @"Descripción del estudio");
    form.compress = [NSButton checkboxWithTitle:@"Achicar (máx. 1600 px) y comprimir JPEG" target:nil action:nil];
    form.compress.state = NSControlStateValueOn;
    form.saveCopy = [NSButton checkboxWithTitle:@"Guardar también una copia en Descargas" target:nil action:nil];

    NSMutableArray *rows = [NSMutableArray array];
    if (selected) {
        form.useSelected = [NSButton checkboxWithTitle:[NSString stringWithFormat:@"Usar paciente seleccionado: %@", selected.displayName] target:form action:@selector(useSelectedChanged:)];
        form.addToStudy = [NSButton checkboxWithTitle:@"Agregar al estudio seleccionado (como serie nueva)" target:form action:@selector(addToStudyChanged:)];
        [rows addObject:@[[NSGridCell emptyContentView], form.useSelected]];
        [rows addObject:@[[NSGridCell emptyContentView], form.addToStudy]];
    }
    [rows addObjectsFromArray:@[
        @[Label(@"Apellido:"), form.last],
        @[Label(@"Nombre:"), form.first],
        @[Label(@"ID paciente:"), form.pid],
        @[Label(@"Estudio:"), form.study],
        @[[NSGridCell emptyContentView], form.compress],
        @[[NSGridCell emptyContentView], form.saveCopy],
    ]];
    NSGridView *grid = [NSGridView gridViewWithViews:rows];
    grid.rowSpacing = 8;
    grid.columnSpacing = 8;
    grid.translatesAutoresizingMaskIntoConstraints = YES;
    [grid setFrameSize:grid.fittingSize];

    if (selected) {
        form.useSelected.state = NSControlStateValueOn;
        [form useSelectedChanged:nil];
    }

    while (YES) {
        NSAlert *alert = [NSAlert new];
        alert.messageText = @"Imagen a DICOM";
        alert.informativeText = [NSString stringWithFormat:@"%lu imagen(es) seleccionada(s).", (unsigned long)count];
        alert.accessoryView = grid;
        [alert addButtonWithTitle:@"Convertir"];
        [alert addButtonWithTitle:@"Cancelar"];
        alert.window.initialFirstResponder = form.last.enabled ? form.last : form.study;
        if ([alert runModal] != NSAlertFirstButtonReturn) return nil;

        if ([form.last.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].length == 0) {
            NSAlert *warn = [NSAlert new];
            warn.messageText = @"Falta el apellido del paciente";
            [warn runModal];
            continue;
        }

        BOOL useSelected = selected && form.useSelected.state == NSControlStateValueOn;
        BOOL addToStudy = useSelected && form.addToStudy.state == NSControlStateValueOn;

        DicomWriter *writer = [DicomWriter new];
        writer.patientLastName = form.last.stringValue;
        writer.patientFirstName = form.first.stringValue;
        writer.patientID = form.pid.stringValue.length ? form.pid.stringValue : @"000001";
        writer.studyDescription = addToStudy ? selected.studyDescription : form.study.stringValue;
        if (useSelected) {
            writer.patientBirthDate = selected.birthDate;
            writer.patientSex = selected.sex;
        }
        if (addToStudy && selected.studyUID.length) {
            writer.existingStudyUID = selected.studyUID;
            writer.existingStudyDate = selected.studyDate;
            writer.existingStudyTime = selected.studyTime;
            writer.existingStudyID = selected.studyID;
            writer.existingAccessionNumber = selected.accession;
        }
        writer.compress = form.compress.state == NSControlStateValueOn;
        writer.maxDimension = writer.compress ? 1600 : 0;
        *saveCopy = form.saveCopy.state == NSControlStateValueOn;
        return writer;
    }
}

#pragma mark - Horos database

// Folder Horos watches and auto-imports from.
- (NSString *)incomingDirectory {
    Class dbClass = NSClassFromString(@"DicomDatabase");
    id db = [dbClass respondsToSelector:@selector(activeLocalDatabase)] ? [dbClass performSelector:@selector(activeLocalDatabase)] : nil;
    if ([db respondsToSelector:@selector(incomingDirPath)]) {
        NSString *p = [db performSelector:@selector(incomingDirPath)];
        if (p.length) return p;
    }
    return nil;
}

- (NSString *)safeFileName:(DicomWriter *)w index:(NSUInteger)i {
    NSString *base = [NSString stringWithFormat:@"%@_%@", w.patientLastName, w.patientFirstName];
    NSCharacterSet *bad = [NSCharacterSet characterSetWithCharactersInString:@"/:\\?%*|\"<> "];
    base = [[base componentsSeparatedByCharactersInSet:bad] componentsJoinedByString:@"_"];
    while ([base hasSuffix:@"_"]) base = [base substringToIndex:base.length - 1];
    return i > 0 ? [NSString stringWithFormat:@"%@_%lu.dcm", base, (unsigned long)i + 1] : [base stringByAppendingString:@".dcm"];
}

#pragma mark - Entry point

- (long)filterImage:(NSString *)menuName {
    // Read the selection before the open panel, while the browser still has focus.
    JTDSelectedStudy *selected = SelectedStudy();
    NSArray<NSURL *> *urls = [self chooseImages];
    if (urls.count == 0) return 0;

    BOOL saveCopy = NO;
    DicomWriter *writer = [self askPatientForCount:urls.count selected:selected saveCopy:&saveCopy];
    if (!writer) return 0;

    NSString *incoming = [self incomingDirectory];
    if (!incoming) {
        NSAlert *a = [NSAlert new];
        a.messageText = @"No se encontró la base de datos de Horos";
        a.informativeText = @"No se pudo ubicar la carpeta de importación (INCOMING).";
        [a runModal];
        return -1;
    }

    NSFileManager *fm = NSFileManager.defaultManager;
    [fm createDirectoryAtPath:incoming withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *downloads = [fm URLsForDirectory:NSDownloadsDirectory inDomains:NSUserDomainMask].firstObject.path;
    NSMutableArray<NSString *> *errors = [NSMutableArray array];
    NSUInteger ok = 0;

    // Stage in a temp folder, then move into INCOMING so Horos never sees half-written files.
    NSString *staging = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
    [fm createDirectoryAtPath:staging withIntermediateDirectories:YES attributes:nil error:nil];

    for (NSUInteger i = 0; i < urls.count; i++) {
        NSError *err = nil;
        NSData *dcm = [writer dicomDataForImageAtPath:urls[i].path error:&err];
        if (!dcm) {
            [errors addObject:err.localizedDescription ?: urls[i].lastPathComponent];
            continue;
        }
        NSString *name = [self safeFileName:writer index:i];

        if (saveCopy) {
            NSString *dst = [downloads stringByAppendingPathComponent:name];
            NSUInteger n = 2;
            while ([fm fileExistsAtPath:dst]) {
                dst = [downloads stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_%lu.dcm", name.stringByDeletingPathExtension, (unsigned long)n++]];
            }
            [dcm writeToFile:dst atomically:YES];
        }

        NSString *staged = [staging stringByAppendingPathComponent:[[NSUUID UUID].UUIDString stringByAppendingPathExtension:@"dcm"]];
        NSString *target = [incoming stringByAppendingPathComponent:staged.lastPathComponent];
        if ([dcm writeToFile:staged atomically:YES] && [fm moveItemAtPath:staged toPath:target error:&err]) {
            ok++;
        } else {
            [errors addObject:[NSString stringWithFormat:@"%@: %@", urls[i].lastPathComponent, err.localizedDescription ?: @"no se pudo guardar"]];
        }
    }
    [fm removeItemAtPath:staging error:nil];

    NSAlert *done = [NSAlert new];
    if (errors.count == 0) {
        done.messageText = [NSString stringWithFormat:@"%lu imagen(es) enviada(s) a Horos", (unsigned long)ok];
        done.informativeText = @"Aparecen en la base de datos en unos segundos.";
    } else {
        done.alertStyle = NSAlertStyleWarning;
        done.messageText = [NSString stringWithFormat:@"%lu de %lu imágenes convertidas", (unsigned long)ok, (unsigned long)urls.count];
        done.informativeText = [errors componentsJoinedByString:@"\n"];
    }
    [done runModal];
    return 0;
}

@end
