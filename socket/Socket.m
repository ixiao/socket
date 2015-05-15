//
//  Socket.m
//  Chat
//
//  Created by 货道网 on 15/5/6.
//  Copyright (c) 2015年 李铁柱. All rights reserved.
//

#import "Socket.h"


@implementation MulticastDelegate
@end


/**
 *  接受数据类用于接受不同数据
 */



@interface Socket ()
{
    NSTimer * autoConnectionTimer; // 自动连接定时器
    
    NSString * socketAddress; // 连接地址
    NSInteger socketPort; // 连接端口
    
    NSInteger receiveMaxLength; // 最大接受长度
    NSMutableData * receiveMData; // 接受到的数据
    
    
    BOOL isConnecting; // 是否正在连接
}


@end


@implementation Socket



- (id) init
{
    self = [super init];
    if (self) {
        
        _socket = [[AsyncSocket alloc] initWithDelegate:self];
        
        
        receiveMData = [[NSMutableData alloc] init];
        _delegates = [[NSMutableArray alloc] init];
        
        currentSendDict = [[NSMutableDictionary alloc] init];
        
    }
    return self;
}


// MARK: - 实例方法


/**
 *  连接socket服务器
 *
 *  @param address 地址
 *  @param port    端口
 *  @param isAuto  是否自动重连
 */
- (void)connectionToIpaddress:(NSString *)address Port:(NSInteger)port isAutoConnection:(BOOL)isAuto
{
    
    socketAddress = [address copy];
    socketPort = port;
    if (isAuto) {
        [autoConnectionTimer invalidate];
        autoConnectionTimer = [NSTimer scheduledTimerWithTimeInterval:3 target:self selector:@selector(connectionSocketServer) userInfo:nil repeats:YES];

    }
    [self connectionSocketServer];
    
}

/**
 *  发送请求到服务器
 *
 *  @param action    请求方法
 *  @param parameter 参数
 */
- (void)sendAction:(Action)action Parameter:(NSDictionary *)parameter
{
    if (!_socket.isConnected) {
        
        NSDictionary * dict = [[NSDictionary alloc] initWithObjectsAndKeys:[NSNumber numberWithInt:action],@"action", @"0" , @"code", @"尚未连接服务器",@"msg", nil];
        [self distributeReceiveData:dict];
        return;
    }
    
    NSMutableDictionary * mDict = [[NSMutableDictionary alloc] initWithDictionary:parameter];
    [mDict setObject:[[NSString alloc] initWithFormat:@"%lu",(unsigned long)action] forKey:@"action"];
    
//    [_socket writeData:[Datagram codingDictonary:mDict] withTimeout:60 tag:currentSendTag];
    
    [currentSendDict setObject:mDict forKey:[NSNumber numberWithInteger:currentSendTag]];
    
    
    
    currentSendTag ++;
}

/**
 *  socket 连接到服务器
 */
- (void)connectionSocketServer
{
    if (_socket.isConnected || isConnecting) {
        return;
    }
    NSError * error;
    isConnecting = [_socket connectToHost:socketAddress onPort:socketPort error:&error];

    if (error) {
        NSLog(@"socket连接失败 %@",[error localizedDescription]);
    }
}

/**
 *  添加接受数据代理
 *
 *  @param delegate 接受对象
 */
- (void)addDelegate:(id)delegate
{
    if (!delegate) {
        return;
    }
    
    MulticastDelegate * md = [[MulticastDelegate alloc] init];
    md.delegate = delegate;
    
    [_delegates addObject:md];

}
/**
 *  删除代理对象
 *
 *  @param delegate 代理对象
 */
- (void)removeDelegate:(id)delegate
{
    if (!delegate) {
        return;
    }
    [_delegates enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        MulticastDelegate * md = obj;
        if (md.delegate == delegate) {
            [_delegates removeObject:md];
            *stop = YES;
        }
        
    }];

}

/**
 *  分发接受到的数据
 *
 *  @param dict data
 */
- (void)distributeReceiveData:(NSDictionary *)dict
{
    
    __block typeof(self) weakSelf = self;
    [_delegates enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        
        MulticastDelegate * md = obj;
        if (md.delegate && [md.delegate respondsToSelector:@selector(socket:ReceiveData:Action:)]) {
            [md.delegate socket:weakSelf ReceiveData:dict Action:[[dict objectForKey:@"action"] integerValue]];
        } else {
            
            [weakSelf->_delegates removeObjectAtIndex:idx];
        }
        
    }];
}

/**
 *  分发发送成功的数据
 *
 *  @param dict      发送的数据
 *  @param isSucceed 是否发送成功
 */
- (void)distributeSendData:(NSDictionary *)dict Succeed:(BOOL)isSucceed
{
    NSDictionary * d = [[NSDictionary alloc] initWithDictionary:dict];
    
    __block typeof(self) weakSelf = self;
    [_delegates enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        MulticastDelegate * md = obj;
        if (md.delegate && [md.delegate respondsToSelector:@selector(socket:SendData:Succeed:Action:)]) {
            [md.delegate socket:weakSelf SendData:d Succeed:isSucceed Action:[[d objectForKey:@"action"] integerValue]];
        } else {
            
            [weakSelf->_delegates removeObjectAtIndex:idx];
        }
        
    }];
}


#pragma mark - AsyncSocket Delegate

/* 成功连接服务器调用此方法 */

- (void)onSocket:(AsyncSocket *)sock didConnectToHost:(NSString *)host port:(UInt16)port
{
    NSLog(@"成功连接服务器");
    
    [sock readDataWithTimeout:-1 tag:0];
    
}

/* 与服务器断开连接调用此方法 */

- (void)onSocketDidDisconnect:(AsyncSocket *)sock
{
    NSLog(@"断开连接");
    
    [sock disconnectAfterReadingAndWriting];
    isConnecting = NO;

}

/* 成功发送数据到服务器调用此方法 */
- (void)onSocket:(AsyncSocket *)sock didWriteDataWithTag:(long)tag
{
    NSLog(@"成功发送数据");
    id obj = [currentSendDict objectForKey:[NSNumber numberWithInteger:tag]];
    [self distributeSendData:obj Succeed:YES];
    [currentSendDict removeObjectForKey:[NSNumber numberWithDouble:tag]];
    
}

/* 发送数据到服务器超时调用此方法 如果返回的值大于0 则视为加长超时时间 */
- (NSTimeInterval)onSocket:(AsyncSocket *)sock
 shouldTimeoutWriteWithTag:(long)tag
                   elapsed:(NSTimeInterval)elapsed
                 bytesDone:(NSUInteger)length
{
    NSLog(@"发送数据超时");
    id obj = [currentSendDict objectForKey:[NSNumber numberWithInteger:tag]];
    [self distributeSendData:obj Succeed:NO];
    [currentSendDict removeObjectForKey:[NSNumber numberWithDouble:tag]];
    return 0;
}

/* 接受到服务器数据调用此方法 */
- (void)onSocket:(AsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag
{
    NSLog(@"接受到数据");
    [sock readDataWithTimeout:-1 tag:0];
    if (receiveMaxLength == 0) {
        
        char * length;
        length = (char *)calloc(4, sizeof(char));
        
        

        receiveMaxLength = length[0] + (length[1] << 8) + (length[2] << 16) + (length[3] << 24);
        [receiveMData setData:[data subdataWithRange:NSMakeRange(4, data.length - 4)]];
        
        if (receiveMaxLength < 0) {
            receiveMaxLength = 0;
        }
        free(length);
        
    } else {
        
        [receiveMData appendData:data];
    }
    if (receiveMData.length >= receiveMaxLength) {
        
//        NSDictionary * dict = [Datagram decodingData:receiveMData];
        
//        [self distributeReceiveData:dict];
        
        receiveMaxLength = 0;
    }
    
}






@end


