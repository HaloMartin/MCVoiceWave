//
//  ViewController.m
//  MCVoiceWave
//
//  Created by 朱进林 on 10/8/16.
//  Copyright © 2016 Martin Choo. All rights reserved.
//

#import "ViewController.h"
#import "MCVoiceWaveView.h"
#import <AVFoundation/AVFoundation.h>

@interface ViewController (){
    BOOL _isSilence;
}
@property (nonatomic, strong) AVAudioRecorder *recorder;
@property (nonatomic, strong) MCVoiceWaveView *voiceWaveView;
@property (nonatomic, strong) UIView *voiceWaveParentView;
@property (nonatomic, strong) NSTimer *updateVolumeTimer;
@property (nonatomic, strong) UIButton *voiceWaveShowButton;
@end

@implementation ViewController

- (void)dealloc
{
    [_voiceWaveView removeFromParent];
//    [_loadingView stopLoading];
    _voiceWaveView = nil;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    [self setupRecorder];
    self.view.backgroundColor = [UIColor whiteColor];
    
    [self.view insertSubview:self.voiceWaveParentView atIndex:0];
    [self.voiceWaveView showInParentView:self.voiceWaveParentView];
    [self.voiceWaveView startVoiceWave];
    
    [[NSRunLoop currentRunLoop] addTimer:self.updateVolumeTimer forMode:NSRunLoopCommonModes];
    
    [self.view addSubview:self.voiceWaveShowButton];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)updateVolume:(NSTimer *)timer
{
    [self.recorder updateMeters];
    //dB = 20*log(normalizedValue),分贝计算公式
    CGFloat normalizedValue = pow (10, [self.recorder averagePowerForChannel:0] / 20);
    [_voiceWaveView changeVolume:normalizedValue];
}

- (void)voiceWaveShowButtonTouched:(UIButton *)sender
{
    _isSilence = !_isSilence;
    [sender setImage:[UIImage imageNamed:_isSilence?@"btn_voice2.png":@"btn_voice1.png"] forState:UIControlStateNormal];
    if (_isSilence) {
        [self.voiceWaveView stopVoiceWave];
        [self.updateVolumeTimer invalidate];
        _updateVolumeTimer = nil;
    }else {
        [self.voiceWaveView showInParentView:self.voiceWaveParentView];
        [self.voiceWaveView startVoiceWave];
        [[NSRunLoop currentRunLoop] addTimer:self.updateVolumeTimer forMode:NSRunLoopCommonModes];
    }
}

-(void)setupRecorder
{
    NSURL *url = [NSURL fileURLWithPath:@"/dev/null"];
    NSDictionary *settings = @{AVSampleRateKey:          [NSNumber numberWithFloat: 44100.0],
                               AVFormatIDKey:            [NSNumber numberWithInt: kAudioFormatAppleLossless],
                               AVNumberOfChannelsKey:    [NSNumber numberWithInt: 2],
                               AVEncoderAudioQualityKey: [NSNumber numberWithInt: AVAudioQualityMin]};
    
    NSError *error;
    self.recorder = [[AVAudioRecorder alloc] initWithURL:url settings:settings error:&error];
    if(error) {
        NSLog(@"Ups, could not create recorder %@", error);
        return;
    }
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord error:&error];
    if (error) {
        NSLog(@"Error setting category: %@", [error description]);
    }
    [self.recorder prepareToRecord];
    [self.recorder setMeteringEnabled:YES];
    [self.recorder record];
}

#pragma mark - getters

- (MCVoiceWaveView *)voiceWaveView
{
    if (!_voiceWaveView) {
        self.voiceWaveView = [[MCVoiceWaveView alloc] init];
    }
    
    return _voiceWaveView;
}

- (UIView *)voiceWaveParentView
{
    if (!_voiceWaveParentView) {
        self.voiceWaveParentView = [[UIView alloc] init];
        CGSize screenSize = [UIScreen mainScreen].bounds.size;
        _voiceWaveParentView.frame = CGRectMake(0, 0, screenSize.width, 320);
    }
    
    return _voiceWaveParentView;
}

- (UIButton *)voiceWaveShowButton
{
    if (!_voiceWaveShowButton) {
        self.voiceWaveShowButton = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, 150, 50)];
        _voiceWaveShowButton.center = CGPointMake(self.view.bounds.size.width / 2.0, self.view.bounds.size.height / 2.0 + 200);
        [_voiceWaveShowButton setImage:[UIImage imageNamed:@"btn_voice1.png"] forState:UIControlStateNormal];
        _voiceWaveShowButton.backgroundColor = [[UIColor grayColor] colorWithAlphaComponent:0.5];
        [_voiceWaveShowButton addTarget:self action:@selector(voiceWaveShowButtonTouched:) forControlEvents:UIControlEventTouchUpInside];
    }
    
    return _voiceWaveShowButton;
}

/** 初始化定时器，每隔0.1秒触发一次，获取振幅系数
 */
- (NSTimer *)updateVolumeTimer
{
    if (!_updateVolumeTimer) {
        self.updateVolumeTimer = [NSTimer timerWithTimeInterval:0.1 target:self selector:@selector(updateVolume:) userInfo:nil repeats:YES];
    }
    
    return _updateVolumeTimer;
}

@end
