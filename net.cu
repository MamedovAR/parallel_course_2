#include <ctime>
#include <cmath>
#include <math.h>
#include <cuda.h>
#include "cublas_v2.h"
#include <stdio.h>
#include <iostream>
#include <stdlib.h>
#define IDX2C(i,j,ld) (((j)*(ld))+(i))
//Класс nn.Linear
class Linear
{
    private:
    double* array;
    double* cuarray;
    int w,h;
    public:
//Инициализация
    Linear(){
        this->w=0;
        this->h=0;
        this->array=NULL;
        this->cuarray=NULL;
//        this->cuout=NULL;
    };
    
    Linear(const Linear& ln)
    {
        cudaMemcpy(this->cuarray,ln.cuarray,ln.w*ln.h,cudaMemcpyDeviceToDevice);
        this->array=ln.array;
        this->h=ln.h;
        this->w=ln.w;
    };
    ~Linear()
    {
        cudaFree(this->cuarray);
//        cudaFree(this->cuout);
        free(array);
    };

    Linear& operator=(const Linear& ln)
    {
	this->cuarray=ln.cuarray;
        this->array=ln.array;
        this->h=ln.h;
        this->w=ln.w;
        return *this;
    };
//Чтение весов из файла
    void initLinear(int a, int b)
    {
        this->array = (double*)malloc(a*b*sizeof(double));
        this->h=a;
        this->w=b;
        FILE* fl;
        if(a==1024)fl = fopen("fc1.bin","rb");
        else if(a==256)fl = fopen("fc2.bin","rb");
        else fl = fopen("fc3.bin","rb");
        float arrf[a*b];
        fread(arrf,sizeof(float),a*b,fl);
        fclose(fl);
        for(int i=0; i<a*b; i++)
            this->array[i]=(double(arrf[i]));//(double)arrf[i];
        cudaMalloc(&this->cuarray,a*b*sizeof(double));
        cudaMemcpy(this->cuarray,this->array,a*b*sizeof(double),cudaMemcpyHostToDevice);
    };
//Прямой проход (умножение на матрицу)
    void forward(double* arr)
    {
        cublasHandle_t handle;
        cublasCreate(&handle);
        double* cuout;
        cudaMalloc(&cuout,this->w*sizeof(double));
	    double skal=1;
        cublasDgemv(handle,CUBLAS_OP_N,this->w,this->h,&skal,this->cuarray,this->w,arr,1,&skal,cuout,1);
        cudaFree(arr);
        cudaMalloc(&arr,this->w*sizeof(double));
        cudaMemcpy(arr,cuout,this->w*sizeof(double),cudaMemcpyDeviceToDevice);
        cublasDestroy(handle);
        cudaFree(cuout);
    };
};
//Сигмоида
__device__ double sigma(double x)
{
    return 1 / (1 + std::exp(-x));
}
//Параллельный вызов сигмоиды
__global__ void sigmoid(double* arr,int n)
{
    if(IDX2C(threadIdx.x,blockIdx.x,n)<n*n)
    	arr[IDX2C(threadIdx.x,blockIdx.x,n)]=sigma(arr[IDX2C(threadIdx.x,blockIdx.x,n)]);
}
//Класс нейронной сети
class Net
{
    public:
    Linear fc1,fc2,fc3;
//Инициализация
    Net()
    {
        this->fc1.initLinear(32*32,16*16);
        this->fc2.initLinear(16*16,4*4);
        this->fc3.initLinear(4*4,1);
    };
//Прямой проход: полносвязный линейный слой и сигмоида в качестве функции активации
    void forward(double* arr)
    {
        double arr1[32*32];
        cudaMemcpy(arr1,arr,32*32*sizeof(double),cudaMemcpyDeviceToHost);
        //printf("first layer\n");
        this->fc1.forward(arr);
        double arr2[16*16];
        cudaMemcpy(arr2,arr,16*16*sizeof(double),cudaMemcpyDeviceToHost);
        //for(int i=0; i<16; i++)
            //printf("%f\n",arr2[i]);
        sigmoid<<<16,32>>>(arr,16);
        //printf("second layer\n");
        this->fc2.forward(arr);
        cudaMemcpy(arr2,arr,4*4*sizeof(double),cudaMemcpyDeviceToHost);
        //for(int i=0; i<16; i++)
            //printf("%f\n",arr2[i]);
        sigmoid<<<4,32>>>(arr,4);
        //printf("third layer\n");
        this->fc3.forward(arr);
        cudaMemcpy(arr2,arr,sizeof(double),cudaMemcpyDeviceToHost);
        //for(int i=0; i<1; i++)
            //printf("%f\n",arr2[i]);
        arr2[0]=1/(1-exp(-arr2[0]));
//        //printf("%f",arr2[0]);
        sigmoid<<<1,32>>>(arr,1);
    };
};

int main()
{
//Замер времени
    std::time_t result = std::time(nullptr);
    double* array = (double*)malloc(32*32*sizeof(double));
//    float arrf[32*32];
//Чтение входных данных из файла (сгенерировано случайно)
    FILE* fl;
    fl = fopen("start.bin","rb");
    fread(array,sizeof(double),32*32,fl);
    fclose(fl);
//Преобразование типов
//     for(int i=0; i<32*32; i++)
//     {
// //        array[i]=(std::round(array[i]*1e6)/1e6);
//         array[i]=double(arrf[i]);
//     }
    double* cuarr;
    cudaMalloc(&cuarr,32*32*sizeof(double));
    cudaMemcpy(cuarr,array,32*32,cudaMemcpyHostToDevice);
//Инициализация нейронной сети
    Net net;
//Прямой проход нейронной сети
    net.forward(cuarr);
    free(array);
    array=(double*)malloc(sizeof(double));
    cudaMemcpy(array,cuarr,sizeof(double),cudaMemcpyDeviceToHost);
//Освобождение ресурсов
    cudaFree(cuarr);
    printf("Result: %.4f\n",array[0]-0.2765);
    free(array);
    printf("Time: %d\n",std::time(nullptr) - result);
    return 0;
}
