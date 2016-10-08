//
//  MCVoiceWaveView.m
//  MCVoiceWave
//
//  Created by 朱进林 on 10/8/16.
//  Copyright © 2016 Martin Choo. All rights reserved.
//

#import "MCVoiceWaveView.h"

#define voiceWaveDisappearDuration 0.25
#define minVolume 0.05
static NSRunLoop* _voiceWaveRunLoop;

#pragma mark - MCVolumeQueue
@interface MCVolumeQueue()

@property (nonatomic, strong) NSMutableArray* volumeArray;
@end
@implementation MCVolumeQueue

-(instancetype)init
{
    self = [super init];
    if (self) {
        self.volumeArray = [NSMutableArray array];
    }
    return self;
}
-(void)pushVolume:(CGFloat)volume
{
    if (volume >= minVolume) {
        [_volumeArray addObject:[NSNumber numberWithFloat:volume]];
    }
}
-(void)pushVolumeWithArray:(NSArray *)array
{
    if (array.count > 0) {
        for (NSInteger i = 0; i < array.count; i++) {
            CGFloat volume = [array[i] floatValue];
            [self pushVolume:volume];
        }
    }
}
-(CGFloat)popVolume
{
    CGFloat volume = -10;
    if (_volumeArray.count > 0) {
        volume = [[_volumeArray firstObject] floatValue];
        [_volumeArray removeObjectAtIndex:0];
    }
    return volume;
}
-(void)cleanQueue
{
    if (_volumeArray) {
        [_volumeArray removeAllObjects];
    }
}
@end

#pragma mark - MCVoiceWaveView
@interface MCVoiceWaveView(){
    CGFloat _idleAmplitude;//最小振幅
    CGFloat _amplitude;//振幅系数，表示音量在屏幕上高度的比例
    CGFloat _density;//X轴粒度，粒度越小，线条越顺
    CGFloat _waveHeight;//波形图所在view的高
    CGFloat _waveWidth;//波形图所在view的宽
    CGFloat _waveMid;//波形图所在view的中点
    CGFloat _maxAmplitude;//最大振幅
    //可以多画几根线，使声波波形看起来更复杂真实
    CGFloat _phase;//初始相位位移
    CGFloat _phaseShift;//_phase累进的相位位移量，造成向前推移的感觉
    CGFloat _frequencyFirst;//firstLine在view上的频率
    CGFloat _frequencySecond;//secondLine在view上的频率
    //
    CGFloat _currentVolume;//音量相关
    CGFloat _lastVolume;
    CGFloat _middleVolume;
    //
    CGFloat _maxWidth;//波纹显示最大宽度
    CGFloat _beginX;//波纹开始坐标
    CGFloat _stopAnimationRatio;//衰减系数,停止后避免音量过大，波纹振幅大，乘以衰减系数
    BOOL _isStopAnimating;//正在进行消失动画
    //
    UIBezierPath* _firstLayerPath;
    UIBezierPath* _secondLayerPath;
}
@property (nonatomic, strong) CADisplayLink* displayLink;
@property (nonatomic, strong) CAShapeLayer* firstShapeLayer;
@property (nonatomic, strong) CAShapeLayer* secondShapeLayer;
@property (nonatomic, strong) CAShapeLayer* fillShapeLayer;
//
@property (nonatomic, strong) UIImageView* firstLine;
@property (nonatomic, strong) UIImageView* secondLine;
@property (nonatomic, strong) UIImageView* fillLayerImage;
//
@property (nonatomic, strong) MCVolumeQueue* volumeQueue;

@end
@implementation MCVoiceWaveView

-(void)setup
{
    _frequencyFirst = 2.0f;//2个周期
    _frequencySecond = 1.8f;//1.6个周期，更平缓，有点周期差，使图像看起来更有错落感
    
    _amplitude = 1.0f;
    _idleAmplitude = 0.01f;
    
    _phase = 0.0f;
    _phaseShift = -0.22f;
    _density = 1.f;
    
    _waveHeight = CGRectGetHeight(self.bounds);
    _waveWidth  = CGRectGetWidth(self.bounds);
    _waveMid    = _waveWidth / 2.0f;
    _maxAmplitude = _waveHeight * 0.5;
    
    _maxWidth = _waveWidth + _density;
    _beginX = 0.0;
    
    _lastVolume = 0.0;
    _currentVolume = 0.0;
    _middleVolume = 0.01;
    _stopAnimationRatio = 1.0;
    
    [_volumeQueue cleanQueue];
}

-(instancetype)init
{
    self = [super init];
    if (self) {
        [self startVoiceWaveThread];
    }
    return self;
}

-(void)dealloc
{
    [_displayLink invalidate];
}

-(void)voiceWaveThreadEntryPoint:(id)__unused object
{
    @autoreleasepool {
        [[NSThread currentThread] setName:@"com.anxin-net.VoiceWave"];
        _voiceWaveRunLoop = [NSRunLoop currentRunLoop];
        [_voiceWaveRunLoop addPort:[NSMachPort port] forMode:NSDefaultRunLoopMode];
        [_voiceWaveRunLoop run];
    }
}

-(NSThread*)startVoiceWaveThread
{
    static NSThread* _voiceWaveThread = nil;
    static dispatch_once_t oncePredicate;
    dispatch_once(&oncePredicate, ^{
        _voiceWaveThread = [[NSThread alloc] initWithTarget:self selector:@selector(voiceWaveThreadEntryPoint:) object:nil];
        [_voiceWaveThread start];
    });
    return _voiceWaveThread;
}

-(void)showInParentView:(UIView *)parentView
{
    if (![self.superview isKindOfClass:[parentView class]] || !_isStopAnimating) {
        [parentView addSubview:self];
    }else {
        [self.layer removeAllAnimations];
        return;
    }
    //
    self.frame =CGRectMake(0, 0, parentView.bounds.size.width, parentView.bounds.size.height);
    [self setup];
    //
    [self addSubview:self.firstLine];
    self.firstLine.frame = self.bounds;
    CGFloat firstLineWidth = 5 / [UIScreen mainScreen].scale;
    self.firstShapeLayer = [self generateShaperLayerWithLineWidth:firstLineWidth];
    self.firstLine.layer.mask = self.firstShapeLayer;
    //
    [self addSubview:self.secondLine];
    self.secondLine.frame = self.bounds;
    CGFloat secondLineWidth = 4 / [UIScreen mainScreen].scale;
    self.secondShapeLayer = [self generateShaperLayerWithLineWidth:secondLineWidth];
    self.secondLine.layer.mask = self.secondShapeLayer;
    //
    [self addSubview:self.fillLayerImage];
    _fillLayerImage.frame = self.bounds;
    _fillLayerImage.layer.mask = self.fillShapeLayer;
    //
    [self updateMeters];
}

-(void)startVoiceWave
{
    if (_isStopAnimating) {
        return;
    }
    [self setup];
    if (_voiceWaveRunLoop) {
        [self.displayLink invalidate];
        self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(invokeWaveCallback)];
        [self.displayLink addToRunLoop:_voiceWaveRunLoop forMode:NSRunLoopCommonModes];
    }else {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (_voiceWaveRunLoop) {
                [self.displayLink invalidate];
                self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(invokeWaveCallback)];
                [self.displayLink addToRunLoop:_voiceWaveRunLoop forMode:NSRunLoopCommonModes];
            }
        });
    }
}

-(void)stopVoiceWave
{
    if (_isStopAnimating) {
        return;
    }
    [self.layer removeAllAnimations];
    _isStopAnimating = YES;
}

-(void)changeVolume:(CGFloat)volume
{
    @synchronized (self) {
        _lastVolume = _currentVolume;
        _currentVolume = volume;
        //
        NSArray* volumeArray = [self generatePointsOfSize:6 withPowFactor:1 fromStartY:_lastVolume toEndY:_currentVolume];
        [self.volumeQueue pushVolumeWithArray:volumeArray];
    }
}

-(void)removeFromParent
{
    [_displayLink invalidate];
    [self removeFromSuperview];
}

-(void)invokeWaveCallback
{
    [self updateMeters];
}

-(void)updateMeters
{
    CGFloat volume = [self.volumeQueue popVolume];
    if (volume > 0) {
        _middleVolume = volume;
    }else {
        _middleVolume -= 0.01;
    }
    _phase += _phaseShift;
    _amplitude = fmax(_middleVolume, _idleAmplitude);
    if (_isStopAnimating) {
        _stopAnimationRatio -=0.05;
        _stopAnimationRatio = fmax(_stopAnimationRatio, 0.01);
        if (_stopAnimationRatio == 0.01) {
            [self animationStopped];
        }
    }
    _firstLayerPath = nil;
    _secondLayerPath = nil;
    _firstLayerPath = [self generateBezierPathWithFrequency:_frequencyFirst maxAmplitude:_maxAmplitude phase:_phase];
    _secondLayerPath = [self generateBezierPathWithFrequency:_frequencySecond maxAmplitude:_maxAmplitude * 0.8 phase:_phase+3];
    //
    NSDictionary* dic = @{@"firstPath":_firstLayerPath,@"secondPath":_secondLayerPath};
    [self performSelectorOnMainThread:@selector(updateShapeLayerPath:) withObject:dic waitUntilDone:NO];
}

-(void)updateShapeLayerPath:(NSDictionary*)dic
{
    UIBezierPath* firstPath = [dic objectForKey:@"firstPath"];
    _firstShapeLayer.path = firstPath.CGPath;
    UIBezierPath* secondPath = [dic objectForKey:@"secondPath"];
    _secondShapeLayer.path = secondPath.CGPath;
    if (firstPath && secondPath) {
        UIBezierPath* fillPath = [UIBezierPath bezierPathWithCGPath:firstPath.CGPath];
        [fillPath appendPath:secondPath];
        [fillPath closePath];
        _fillShapeLayer.path = fillPath.CGPath;
    }
}

-(void)animationStopped
{
    [self.displayLink invalidate];
    _isStopAnimating = NO;
    //
    self.layer.mask = nil;
    _lastVolume = 0.0;
    _currentVolume = 0.0;
    _middleVolume = 0.05;
    [_volumeQueue cleanQueue];
}

#pragma mark - generate
-(CAShapeLayer*)generateShaperLayerWithLineWidth:(CGFloat)lineWidth
{
    CAShapeLayer* waveLine = [CAShapeLayer layer];
    waveLine.lineCap = kCALineCapButt;
    waveLine.lineJoin = kCALineJoinRound;
    waveLine.strokeColor = [UIColor redColor].CGColor;
    waveLine.fillColor = [UIColor clearColor].CGColor;
    waveLine.lineWidth = lineWidth;
    waveLine.backgroundColor = [UIColor clearColor].CGColor;
    return  waveLine;
}
/** 根据频率，最大振幅，相位等信息，得到代表当前音量的波形
 */
-(UIBezierPath*)generateBezierPathWithFrequency:(CGFloat)frequency maxAmplitude:(CGFloat)maxAmplitude phase:(CGFloat)phase
{
    UIBezierPath* waveLinePath = [UIBezierPath bezierPath];
    CGFloat normedAmplitude = fmin(_amplitude, 1.0);//振幅百分比，最高只能是1
    //按X轴粒度连接多个点，拼接在一起，形成类似曲线的波形
    for (CGFloat x = _beginX; x < _maxWidth; x += _density) {
        CGFloat scaling = (1+cosf(M_PI+(x/_maxWidth)*2*M_PI))/2;
        CGFloat y = scaling * _maxAmplitude * normedAmplitude * _stopAnimationRatio * sinf(2 * M_PI * (x / _waveWidth) * frequency + phase) + (_waveHeight * 0.5);
        if (_beginX == x) {
            [waveLinePath moveToPoint:CGPointMake(x, y)];
        }else {
            [waveLinePath addLineToPoint:CGPointMake(x, y)];
        }
    }
    return waveLinePath;
}
/**插值方法，在相邻的两个值中间，插入若干个值，使波形切换时过渡更平滑*/
-(NSArray*)generatePointsOfSize:(NSInteger)size withPowFactor:(CGFloat)factor fromStartY:(CGFloat)startY toEndY:(CGFloat)endY
{
    BOOL factorValid = factor < 2 && factor > 0 && factor != 0;
    BOOL startYValid = 0 <= startY && startY <= 1;
    BOOL endYValid = 0 <= endY && endY <= 1;
    if (!(factorValid && startYValid && endYValid)) {
        return nil;
    }
    //
    NSMutableArray* mArray = [NSMutableArray arrayWithCapacity:size];
    CGFloat startX,endX;
    startX = pow(startY, 1/factor);
    endX = pow(endY, 1/factor);
    //
    CGFloat pieceOfX = (endX - startX) / size;
    CGFloat x,y;
    [mArray addObject:[NSNumber numberWithFloat:startY]];
    for (int i = 1; i < size; ++i) {
        x = startX + pieceOfX * i;
        y = pow(x, factor);
        [mArray addObject:[NSNumber numberWithFloat:y]];
    }
    return [mArray copy];
}
#pragma mark - getter
-(UIImageView*)firstLine
{
    if (!_firstLine) {
        self.firstLine = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"pic_firstLine.png"]];
        _firstLine.layer.masksToBounds = YES;
    }
    return _firstLine;
}
-(UIImageView*)secondLine
{
    if (!_secondLine) {
        self.secondLine = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"pic_secondLine.png"]];
        _secondLine.layer.masksToBounds = YES;
        _secondLine.alpha = 0.6;
    }
    return _secondLine;
}
-(UIImageView*)fillLayerImage
{
    if (!_fillLayerImage) {
        self.fillLayerImage = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"pic_fill.png"]];
        _fillLayerImage.layer.masksToBounds = YES;
        _fillLayerImage.alpha = 0.2;
    }
    return _fillLayerImage;
}
-(CAShapeLayer*)fillShapeLayer
{
    if (!_fillShapeLayer) {
        self.fillShapeLayer = [CAShapeLayer layer];
        _fillShapeLayer.lineCap = kCALineCapButt;
        _fillShapeLayer.lineJoin = kCALineJoinRound;
        _fillShapeLayer.strokeColor = [UIColor clearColor].CGColor;
        _fillShapeLayer.fillColor = [UIColor redColor].CGColor;
        _fillShapeLayer.fillRule = @"even-odd";
        _fillShapeLayer.lineWidth = 2;
        _fillShapeLayer.backgroundColor = [UIColor clearColor].CGColor;
    }
    return _fillShapeLayer;
}
-(MCVolumeQueue*)volumeQueue
{
    if (!_volumeQueue) {
        self.volumeQueue = [[MCVolumeQueue alloc] init];
    }
    return _volumeQueue;
}
@end
