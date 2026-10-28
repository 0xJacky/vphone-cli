// Logging, the one-shot experiment flags, and the KVC and ivar readers
// every other section reads SpringBoard and FrontBoard objects through.

#import "FoldDisplayPrivate.h"

void vpFoldDisplayLog(NSString *line) {
    int fd = open("/var/mobile/Library/Caches/vphone-folddisplay.log",
                  O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0666);
    if (fd < 0)
        return;
    NSString *stamp = [NSDateFormatter localizedStringFromDate:NSDate.date
                                                     dateStyle:NSDateFormatterNoStyle
                                                    timeStyle:NSDateFormatterMediumStyle];
    NSString *row = [NSString stringWithFormat:@"%@ %@\n", stamp, line];
    const char *bytes = row.UTF8String;
    if (bytes)
        write(fd, bytes, strlen(bytes));
    close(fd);
}

BOOL vpConsumeDisplayExperimentFlag(const char *flag) {
    int fd = open(flag, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if (fd < 0) return NO;
    char value = 0;
    ssize_t length = read(fd, &value, 1);
    close(fd);
    unlink(flag);
    return length == 1 && value == '1';
}

id vpReadObject(id object, const char *name) {
    SEL selector = sel_registerName(name);
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments != 2 || signature.methodReturnType[0] != '@') return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

id vpReadMultilineDescription(id object) {
    SEL selector = sel_registerName("descriptionWithMultilinePrefix:");
    Method method = class_getInstanceMethod(object_getClass(object), selector);
    if (!method || strcmp(method_getTypeEncoding(method), "@24@0:8@16") != 0) return nil;
    return ((id (*)(id, SEL, id))objc_msgSend)(object, selector, @"");
}

id vpReadObjectIvar(id object, const char *name) {
    Ivar ivar = class_getInstanceVariable(object_getClass(object), name);
    const char *type = ivar ? ivar_getTypeEncoding(ivar) : NULL;
    return type && type[0] == '@' ? object_getIvar(object, ivar) : nil;
}

id vpRootServerScenes(id app) {
    return vpReadObject(vpReadObject(app, "displayProfileManager"), "fbScenes");
}

NSNumber *vpReadBoolValue(id object, const char *name) {
    SEL selector = sel_registerName(name);
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments != 2 ||
        (signature.methodReturnType[0] != 'B' && signature.methodReturnType[0] != 'c')) return nil;
    return @(((BOOL (*)(id, SEL))objc_msgSend)(object, selector));
}

NSValue *vpReadRectValue(id object, const char *name) {
    SEL selector = sel_registerName(name);
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments != 2 ||
        strcmp(signature.methodReturnType, "{CGRect={CGPoint=dd}{CGSize=dd}}") != 0) return nil;
    CGRect value = ((CGRect (*)(id, SEL))objc_msgSend)(object, selector);
    return [NSValue value:&value withObjCType:@encode(CGRect)];
}

id vpSnapshotRect(id object, const char *name) {
    NSValue *value = vpReadRectValue(object, name);
    if (!value) return NSNull.null;
    CGRect rect;
    [value getValue:&rect size:sizeof(rect)];
    return @[@(rect.origin.x), @(rect.origin.y), @(rect.size.width), @(rect.size.height)];
}

NSNumber *vpSnapshotScalarIvar(id object, const char *name) {
    Ivar ivar = class_getInstanceVariable(object_getClass(object), name);
    const char *type = ivar ? ivar_getTypeEncoding(ivar) : NULL;
    if (!type) return nil;
    const void *address = (const char *)(__bridge void *)object + ivar_getOffset(ivar);
    if (strcmp(type, "B") == 0 || strcmp(type, "c") == 0) {
        uint8_t value; memcpy(&value, address, sizeof(value)); return @(value != 0);
    }
    if (strcmp(type, "q") == 0) { int64_t value; memcpy(&value, address, sizeof(value)); return @(value); }
    if (strcmp(type, "Q") == 0) { uint64_t value; memcpy(&value, address, sizeof(value)); return @(value); }
    return nil;
}

NSString *vpDescribeLayerContents(id contents) {
    if (!contents) return @"nil";
    @try {
        if (CFGetTypeID((CFTypeRef)contents) == CGImageGetTypeID()) {
            CGImageRef image = (CGImageRef)(__bridge void *)contents;
            return [NSString stringWithFormat:@"image %zux%zu", CGImageGetWidth(image), CGImageGetHeight(image)];
        }
    } @catch (NSException *exception) { }
    NSString *text = [contents description];
    if (text.length > 60) text = [text substringToIndex:60];
    return [NSString stringWithFormat:@"%s %@", object_getClassName(contents), text];
}

// Reads one ivar by its type encoding so numeric and struct state appear
// without calling arbitrary getters.  Unknown layouts stay "?"; nothing is
// synthesized.
static NSString *vpFormatIvarValue(id object, Ivar ivar) {
    const char *type = ivar_getTypeEncoding(ivar);
    if (!type) return @"?";
    void *ptr = (void *)((char *)(__bridge void *)object + ivar_getOffset(ivar));
    switch (type[0]) {
        case 'd': return [NSString stringWithFormat:@"%.6g", *(double *)ptr];
        case 'f': return [NSString stringWithFormat:@"%.6g", (double)*(float *)ptr];
        case 'B': return *(BOOL *)ptr ? @"YES" : @"NO";
        case 'c': return @(*(int8_t *)ptr).stringValue;
        case 'C': return @(*(uint8_t *)ptr).stringValue;
        case 's': return @(*(int16_t *)ptr).stringValue;
        case 'S': return @(*(uint16_t *)ptr).stringValue;
        case 'i': case 'l': return @(*(int32_t *)ptr).stringValue;
        case 'I': case 'L': return @(*(uint32_t *)ptr).stringValue;
        case 'q': return @(*(int64_t *)ptr).stringValue;
        case 'Q': return @(*(uint64_t *)ptr).stringValue;
        case '@': {
            id value = object_getIvar(object, ivar);
            if (!value) return @"nil";
            if ([value isKindOfClass:NSNumber.class]) return [NSString stringWithFormat:@"@ %@", value];
            if ([value isKindOfClass:NSString.class] || [value isKindOfClass:NSValue.class])
                return [NSString stringWithFormat:@"%s %@", object_getClassName(value), value];
            NSString *text = [value description];
            if (text.length > 90) text = [text substringToIndex:90];
            return [NSString stringWithFormat:@"%s %@", object_getClassName(value), text];
        }
        case '{': {
            if (strncmp(type, "{CGRect", 6) == 0) {
                CGRect rect = *(CGRect *)ptr;
                return [NSString stringWithFormat:@"{{%g, %g}, {%g, %g}}", rect.origin.x, rect.origin.y, rect.size.width, rect.size.height];
            }
            if (strncmp(type, "{CGSize", 6) == 0) {
                CGSize size = *(CGSize *)ptr;
                return [NSString stringWithFormat:@"{%g, %g}", size.width, size.height];
            }
            if (strncmp(type, "{CGPoint", 7) == 0) {
                CGPoint point = *(CGPoint *)ptr;
                return [NSString stringWithFormat:@"{%g, %g}", point.x, point.y];
            }
            if (strncmp(type, "{UIEdgeInsets", 13) == 0) {
                // {top,left,bottom,right} as four CGFloats; a local layout so
                // UIKit is not a dependency of this dylib.
                const CGFloat *edges = (const CGFloat *)ptr;
                return [NSString stringWithFormat:@"insets{%g,%g,%g,%g}", edges[0], edges[1], edges[2], edges[3]];
            }
            if (strncmp(type, "{CGAffineTransform", 18) == 0) {
                CGAffineTransform transform = *(CGAffineTransform *)ptr;
                return [NSString stringWithFormat:@"transform{%g,%g,%g,%g,%g,%g}", transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty];
            }
            return @"{struct}";
        }
        case '^': return [NSString stringWithFormat:@"%p", *(void **)ptr];
        default: return @"?";
    }
}

void vpDumpObjectIvars(id object, NSString *label, NSUInteger limit) {
    if (!object) { vpFoldDisplayLog([NSString stringWithFormat:@"%@ ivars: nil", label]); return; }
    Class cls = object_getClass(object);
    unsigned int count = 0;
    Ivar *ivars = class_copyIvarList(cls, &count);
    vpFoldDisplayLog([NSString stringWithFormat:@"%@ ivars: class=%s count=%u", label, class_getName(cls), count]);
    for (unsigned int i = 0; i < count && i < limit; i++) {
        @try {
            vpFoldDisplayLog([NSString stringWithFormat:@"%@ ivar[%u] %s (%s) = %@", label, i,
                ivar_getName(ivars[i]), ivar_getTypeEncoding(ivars[i]) ?: "?",
                vpFormatIvarValue(object, ivars[i])]);
        } @catch (NSException *exception) {
            vpFoldDisplayLog([NSString stringWithFormat:@"%@ ivar[%u] %s exception: %@", label, i,
                ivar_getName(ivars[i]), exception.reason]);
        }
    }
    free(ivars);
}

// The poster extension's hosted scene presentation views keep their portrait
// 669x951 bounds inside the landscape wallpaper tree. Renderer host nodes are
// resized to the wallpaper presenter's current bounds; the PosterBoard
// floating editor keeps its native portrait bounds and is centered instead.
// The notification is cheap and idempotent, so a newly-created editor can be
// reconciled without touching its loading state.
NSString *vpSizeText(CGSize size) {
    return [NSString stringWithFormat:@"{%.0f, %.0f}", size.width, size.height];
}
