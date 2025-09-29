using System.Text;
using System.Text.Json;
using Azure.Messaging.ServiceBus;
using Microsoft.EntityFrameworkCore;
using ProcesaCompra.Data;
using ProcesaCompra.Models;

namespace ProcesaCompra;

public class Worker : BackgroundService
{
    private readonly string _conn;
    private readonly string _queueEntrada;
    private readonly string _queueHombre;
    private readonly string _queueMujer;

    private readonly ServiceBusClient _sbClient;
    private readonly ServiceBusProcessor _processor;
    private readonly IServiceProvider _sp;

    public Worker(IConfiguration cfg, IServiceProvider sp)
    {
        _sp = sp;

        _conn = cfg["ServiceBus:ConnectionString"]
            ?? Environment.GetEnvironmentVariable("SERVICEBUS_CONNECTION_STRING")
            ?? throw new InvalidOperationException("Falta SERVICEBUS_CONNECTION_STRING");

        _queueEntrada = cfg["ServiceBus:QueueName"]
            ?? Environment.GetEnvironmentVariable("SERVICE_BUS_QUEUE_NAME")
            ?? "compras";

        // Destinos (Basic tier = colas, no topics)
        _queueHombre = cfg["ServiceBus:QueueHombre"]
            ?? Environment.GetEnvironmentVariable("HOMBRE_QUEUE_NAME")
            ?? "hombreq";

        _queueMujer = cfg["ServiceBus:QueueMujer"]
            ?? Environment.GetEnvironmentVariable("MUJER_QUEUE_NAME")
            ?? "mujerq";

        _sbClient = new ServiceBusClient(_conn);

        _processor = _sbClient.CreateProcessor(_queueEntrada, new ServiceBusProcessorOptions
        {
            AutoCompleteMessages = false,
            MaxConcurrentCalls = 2,
            PrefetchCount = 10
        });

        _processor.ProcessMessageAsync += OnMessageAsync;
        _processor.ProcessErrorAsync += OnErrorAsync;
    }

    private async Task OnMessageAsync(ProcessMessageEventArgs args)
    {
        try
        {
            var body = Encoding.UTF8.GetString(args.Message.Body);
            var doc = JsonDocument.Parse(body).RootElement;

            var nombre = doc.GetProperty("Nombre").GetString() ?? "";
            var genero = (doc.TryGetProperty("Genero", out var g) ? g.GetString() : null)?.ToLowerInvariant() ?? "";

            decimal monto = 0m;
            if (doc.TryGetProperty("Monto", out var m) && m.ValueKind != JsonValueKind.Null)
            {
                if (m.ValueKind == JsonValueKind.Number && m.TryGetDecimal(out var parsed))
                    monto = parsed;
                else if (m.ValueKind == JsonValueKind.String && decimal.TryParse(m.GetString(), out var parsedStr))
                    monto = parsedStr;
            }

            var fecha = DateTimeOffset.UtcNow;
            if (doc.TryGetProperty("Fecha", out var f) && f.ValueKind == JsonValueKind.String)
                DateTimeOffset.TryParse(f.GetString(), out fecha);

            if (genero != "hombre" && genero != "mujer")
                throw new InvalidOperationException("Genero inválido");

            // 1) Persistir en BD
            using var scope = _sp.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<ComprasDbContext>();
            db.Compras.Add(new Compra { Nombre = nombre, Genero = genero, Monto = monto, Fecha = fecha });
            await db.SaveChangesAsync();

            // 2) "Fan-out" con colas (Basic tier)
            var destino = genero == "hombre" ? _queueHombre : _queueMujer;
            var sender = _sbClient.CreateSender(destino);

            var forwardMsg = new ServiceBusMessage(args.Message.Body)
            {
                ContentType = "application/json",
                CorrelationId = args.Message.CorrelationId ?? Guid.NewGuid().ToString()
            };
            forwardMsg.ApplicationProperties["genero"] = genero;

            await sender.SendMessageAsync(forwardMsg);

            // 3) Completar mensaje de entrada
            await args.CompleteMessageAsync(args.Message);

            Console.WriteLine($"[OK] Compra de {nombre} ({genero}) ${monto} -> cola '{destino}' y persistida");
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[ERR] {ex.Message}");
            await args.AbandonMessageAsync(args.Message);
        }
    }

    private Task OnErrorAsync(ProcessErrorEventArgs args)
    {
        Console.WriteLine($"[SB-ERROR] {args.Exception.Message}");
        return Task.CompletedTask;
    }

    public override async Task StartAsync(CancellationToken cancellationToken)
    {
        await base.StartAsync(cancellationToken);
        await _processor.StartProcessingAsync(cancellationToken);
        Console.WriteLine($"[START] Escuchando cola entrada '{_queueEntrada}'. Destinos: hombre='{_queueHombre}', mujer='{_queueMujer}'");
    }

    public override async Task StopAsync(CancellationToken cancellationToken)
    {
        await _processor.StopProcessingAsync(cancellationToken);
        await base.StopAsync(cancellationToken);
        Console.WriteLine("[STOP] Procesador detenido");
    }

    protected override Task ExecuteAsync(CancellationToken stoppingToken) => Task.CompletedTask;
}